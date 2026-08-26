# AGENTS.md

Repository-specific instructions for coding agents working on `asdf-agg`.

## Read order and sources of truth

Read in this order before changing behavior:

1. the current issue or request and its acceptance criteria;
2. this file;
3. `CONTRIBUTING.md` and the relevant `README.md` sections;
4. the affected `bin/`, `lib/`, tests, scripts, and CI workflow;
5. mutable external contracts on which the change depends.

Mutable contracts include the official asdf plugin documentation, current `asdf-vm/asdf-plugin-template` conventions where applicable, current `asdf-vm/actions/plugin-test`, and actual `asciinema/agg` tags, releases, assets, and CLI version output. Verify them from primary sources; do not rely on memory or guessed asset names. Report conflicts between acceptance criteria, repository behavior, and upstream contracts.

## Scope and implementation

- Make the smallest clear change that satisfies the issue. Do not perform unrelated refactoring, cleanup, dependency changes, tooling expansion, or speculative abstraction.
- Keep this repository focused on installing `agg` through asdf with minimum dependencies and portable Bash on supported Linux and macOS targets.
- Prefer official prebuilt `asciinema/agg` binaries. Do not add source/Cargo fallback, Windows support, prerelease installation, release automation, or shortname-index work unless the issue explicitly puts it in scope.
- Keep OS, architecture, libc, release asset, and URL mapping explicit and testable. Fail clearly for unsupported combinations; never substitute a binary for another OS, architecture, or libc.
- Stable version discovery must exclude prereleases and must not hardcode the current latest release.

## Regression and verification

Use regression-first development for behavior changes. Add a deterministic failing case before or with the implementation when practical. Live GitHub requests support integration evidence; they do not replace deterministic tests for version parsing, ordering, mapping, URLs, validation, or install safety.

Use coverage terms precisely:

- `scripts/test.bash` runs deterministic local regression tests, including mocked platform cases.
- `scripts/lint.bash` runs ShellCheck and shfmt checks.
- `.github/workflows/ci.yml` defines actionlint, cross-OS deterministic tests, real current-asdf platform integrations, and the exact minimum-asdf gate.

Mocked `uname`, libc, or asset tests are not real execution on that platform. A green workflow is not sufficient evidence by itself: inspect that each relevant integration job actually added the plugin, resolved and installed a real release, selected it, and ran `asdf exec agg --version`.

Before completion, run all applicable free checks:

- focused tests for changed behavior;
- the full deterministic suite;
- ShellCheck and shfmt;
- actionlint for workflow changes;
- applicable real current and minimum asdf integration;
- `git diff --check`;
- final diff review against the issue and acceptance criteria.

If a check cannot run, report the exact gap. Paid APIs, LLM/eval gates, billable benchmarks, and other billable checks require explicit confirmation. Normal free tests, lint, builds, public upstream metadata checks, and GitHub/asdf integration are allowed.

## Git and delivery

- Work from current `main` on one focused branch; do not implement directly on `main`.
- Keep Conventional Commit-style commits focused and do not rewrite published shared history. If a published working branch genuinely must be rewritten, use only `--force-with-lease`, then re-inspect the diff and rerun applicable checks.
- Review the final diff for unrelated scope, TODOs, workarounds, documentation drift, and whitespace errors.
- Unless delivery is explicitly local-only, commit verified changes, push the branch, and create one Draft PR to `main`. Update the existing branch and PR for follow-up fixes instead of opening duplicates.
- Keep the PR description aligned with actual implementation, checks, integration platforms, compatibility minimum, limitations, and issue-closing references.
- Do not run paid gates or publish releases/index submissions as an implied part of ordinary PR delivery.

## Final report

Report evidence rather than command narration. Include changed components, deterministic/static results, real versions and platforms exercised, minimum asdf proof, known limitations or gaps, branch and commit SHAs, Draft PR URL, `git diff --check`, clean-worktree and remote-HEAD confirmation, commit author identity, and issue scope.
