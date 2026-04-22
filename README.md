# nf-test-asserter

**Experimental, alpha.** Companion tooling for a two-phase nf-test launcher targeting Seqera Platform.

## Why

When regenerating nf-test snapshots for a pipeline on a remote compute environment, the naive flow is:

1. Launch the pipeline on Platform.
2. Pull every published output back to the submitter.
3. Run nf-test assertions locally to generate the new `.nf.test.snap` file.

Step 2 moves hundreds of MB (sometimes GB) over the public internet for the sake of regenerating one tiny text file. It also requires the submitter to have cloud credentials for the output bucket.

This pipeline replaces step 2+3 with a single process running **inside** the same compute environment where the pipeline just ran. It:

- clones the pipeline repo at the pinned revision,
- re-invokes the pipeline via `nextflow run -resume <session>` so every task cache-hits (negligible compute),
- lets `nf-test --update-snapshot` evaluate the assertion block against the real `publishDir` contents and a real `workflow.trace`,
- publishes only the regenerated `*.nf.test.snap` file.

The submitter then only needs to fetch a few kilobytes back.

## Invocation

```bash
nextflow launch seqera-services/nf-test-asserter \
    -compute-env <your-CE> \
    --pipeline_repo https://github.com/nf-core/rnaseq \
    --pipeline_rev 7e5a4d579cc3a067cd2b15043913aabe5d673fb8 \
    --test_file tests/nofasta.nf.test \
    --outdir_uri s3://your-bucket/nftest-outputs/<testHash> \
    --session_id <phase-1-session-uuid> \
    --test_profile test \
    --outdir s3://your-bucket/nftest-snaps/<testHash>
```

Intended to be driven by the two-phase launcher in a patched `nf-test`, not by humans directly.

## Container

Pinned static Wave image. See `environment.yml` for the conda spec. To rebuild:

```bash
wave --conda-file environment.yml --platform linux/amd64 --freeze --await
```

and update the `container` directive in `main.nf`.

## Status

Prototype. Contracts and param names will change without notice.
