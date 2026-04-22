#!/usr/bin/env nextflow

/*
 * nf-test-asserter
 *
 * Runs an nf-test pipeline test inside a Seqera Platform compute environment,
 * cache-hitting a previously-completed run via `-resume`, and publishes only
 * the regenerated <testFile>.nf.test.snap file.
 *
 * Expected params:
 *   --pipeline_repo   git URL of the pipeline under test (e.g. https://github.com/nf-core/rnaseq)
 *   --pipeline_rev    git revision (branch, tag, or commit SHA)
 *   --test_file       path (relative to repo root) of the .nf.test file
 *   --outdir_uri      URI that was used as params.outdir in phase-1 (e.g. s3://bucket/nftest-outputs/<hash>)
 *   --session_id      the Nextflow session UUID from phase-1 (used with -resume)
 *   --test_profile    nf-test / Nextflow profile to apply (default 'test')
 *   --outdir          where this pipeline publishes the regenerated .snap (required by Nextflow)
 */

params.pipeline_repo = null
params.pipeline_rev  = null
params.test_file     = null
params.outdir_uri    = null
params.session_id    = null
params.test_profile  = 'test'
params.outdir        = null

process ASSERT_SNAPSHOT {

    container 'community.wave.seqera.io/library/nf-test-asserter:9693f5d202ade68f'

    publishDir params.outdir, mode: 'copy'

    input:
    val pipeline_repo
    val pipeline_rev
    val test_file
    val outdir_uri
    val session_id
    val test_profile

    output:
    path "*.nf.test.snap", optional: true, emit: snap
    path "asserter.log",                    emit: log

    script:
    """
    set -euo pipefail

    mkdir -p pipeline
    git clone --no-checkout --depth 50 '${pipeline_repo}' pipeline
    ( cd pipeline && git fetch --depth 1 origin '${pipeline_rev}' || git fetch origin )
    ( cd pipeline && git checkout '${pipeline_rev}' )

    cd pipeline

    # Rewrite params.outdir in the test invocation to the already-published
    # S3 prefix from phase-1 so nf-test sees the real outputs.
    cat > .nftest-asserter-override.config <<CFG
    params.outdir = '${outdir_uri}'
CFG

    # Run nf-test with -resume so Nextflow cache-hits every process (same
    # workDir + session as phase-1), giving us a real workflow.trace object
    # for assertions. Actual compute is negligible under -resume.
    nf-test test '${test_file}' \\
        --update-snapshot \\
        --profile=+${test_profile} \\
        --verbose \\
        -- -resume '${session_id}' -c .nftest-asserter-override.config \\
        > ../asserter.log 2>&1 || true

    cd ..

    # Surface any regenerated .snap files next to this task's workdir so they
    # get captured by publishDir.
    find pipeline -name "*.nf.test.snap" -newer asserter.log -exec cp {} . \\;
    """
}

workflow {
    if (!params.pipeline_repo || !params.pipeline_rev || !params.test_file
            || !params.outdir_uri || !params.session_id || !params.outdir) {
        error "Missing required params. See main.nf header for the full list."
    }
    ASSERT_SNAPSHOT(
        params.pipeline_repo,
        params.pipeline_rev,
        params.test_file,
        params.outdir_uri,
        params.session_id,
        params.test_profile,
    )
}
