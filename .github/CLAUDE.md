# GitHub Actions

## Pinning actions

Always pin actions to **full commit SHAs**, never tags — tags are a supply-chain risk. Include the reference as a trailing comment. When adding a new action, look up the latest stable release tag on GitHub and resolve it to its commit SHA (`git ls-remote`). For annotated tags, use the dereferenced `^{}` SHA.

```yaml
- uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
```

## Step naming

Always name every step. Use the convention `[TYPE] | Action`:

```yaml
- name: "[Setup] | Checkout"
  uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0

- name: "[Setup] | Mise"
  uses: jdx/mise-action@e6a8b3978addb5a52f2b4cd9d91eafa7f0ab959d # v4.2.0

- name: "[Build] | Compile binary"
  shell: bash -euo pipefail {0}
  run: go build -o bin/htmlup ./cmd/htmlup
```

## Comments

Step names already say _what_ a step does — don't restate it in a comment. Add a comment only for non-obvious _why_: a gotcha or constraint not visible from the step itself (e.g. why a tag is pushed with an App token rather than `GITHUB_TOKEN`). Keep it to one line. When in doubt, omit.

## Shell steps

Always set `shell` explicitly. Use `bash -euo pipefail {0}` to fail on errors, unset variables, and broken pipes:

```yaml
- name: "[Test] | Run checks"
  shell: bash -euo pipefail {0}
  run: mise run check
```

## Run names

Every workflow sets `run-name:` dynamically so a run is identifiable at a glance
from the Actions list. Start with the ref in brackets, then use the push commit
message or pull request title, falling back to the workflow name for events that
do not carry either value. Workflow `name:` is **lowercase** by convention.

```yaml
name: ci
run-name: "[${{ github.ref_name }}] ${{ github.event.head_commit.message || github.event.pull_request.title || github.workflow }}"
```

Reusable workflows run nested under the caller, so their `run-name` is cosmetic.

## Workflows

| Workflow      | Trigger                              | What                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------- | ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci.yaml`     | every push, PR to `master`, `workflow_call` | `mise run check:fmt` (swift-format lint, strict) + `mise run check:build` (`swift build`) + `mise run check:structure` (one top-level type per file) + `mise run test` (Swift Testing). Runs on `macos-26` (arm64) with mise `experimental: true` (core swift backend) and an `actions/cache` on `.build` keyed by `Package.resolved`. Reusable so `release.yml` can gate on it. |
| `release.yml` | manual (`workflow_dispatch`)         | read the single checked-in release version from `VERSION` → fail if the `v<version>` tag or GitHub release already exists → `ci.yaml` → create and push the tag, then **stops**. The tag is pushed with a GitHub App token (`RELEASE_APP_*`), not `GITHUB_TOKEN`, so the push triggers `publish.yml` (`GITHUB_TOKEN` pushes do not start workflow runs). |
| `publish.yml` | `push` of a `v*` tag                 | validates `VERSION` matches the tag and Sparkle keys exist (repo variable `SPARKLE_PUBLIC_ED_KEY`, secret `SPARKLE_ED_PRIVATE_KEY`), builds the `.app` via `mise run build` (`mise-tasks/bundle.nu`: Info.plist stamped with `VERSION` + `SPARKLE_PUBLIC_ED_KEY`, bundled yt-dlp, Sparkle.framework, ad-hoc codesign), packages a `.dmg` (`hdiutil`, app + Applications symlink), generates `appcast.xml` with Sparkle's `generate_appcast` signed by `SPARKLE_ED_PRIVATE_KEY`, publishes both via `softprops/action-gh-release`, then generates the Homebrew cask (`.dmg` URL/sha256, quarantine-strip `postflight`) and pushes it to `truehhart/homebrew-tap` (App token from `RELEASE_APP_*`, scoped to `homebrew-tap`). The `.dmg` doubles as the Sparkle update archive. Bundles are **unsigned** by Apple (ad-hoc only); Apple signing/notarization via `APPLE_*` secrets is a later add. **arm64-only**: yt-dlp is bundled as an arch-specific resource. |
