# Contributing

Thanks for contributing to `asdf-agg`.

Create a focused branch from `main`, keep the diff limited to the issue, and add deterministic regression coverage for behavior changes. Verify current asdf and `asciinema/agg` contracts before changing release discovery, platform mapping, download, or install behavior.

Implementation should remain portable Bash with few dependencies. Prefer official prebuilt binaries, explicit platform mappings, stable releases, and clear unsupported-platform errors. Do not add source builds or unrelated infrastructure without an issue that requires them.

Run the applicable local checks before opening a Draft PR:

```sh
scripts/test.bash
scripts/lint.bash
```

CI adds actionlint and real asdf integration across its declared runners, including the minimum supported asdf version. Inspect what those jobs executed instead of treating a green result alone as proof.

See [AGENTS.md](AGENTS.md) for the complete agent workflow and delivery rules.
