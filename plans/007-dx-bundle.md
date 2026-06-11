# Plan 007: DX bundle — formatter, CI caching + lint, CLAUDE.md, dependency pin

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f2dae47..HEAD -- .github/workflows/ci.yml Package.swift README.md`
> Mismatches with the excerpts below are STOP conditions (note: plans 001–006
> change `Sources/`/`Tests/` — that's fine and expected; this plan's formatter
> step intentionally runs AFTER those plans land).

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans 001–006 (ordering only — the formatting pass would conflict with their diffs; run this plan after they merge)
- **Category**: dx
- **Planned at**: commit `f2dae47`, 2026-06-11

## Why this matters

The repo has no formatter/linter, no agent-facing docs, no CI caching, and a dependency floor (`swift-transformers from: 0.1.12`) two dozen patch releases behind the resolved version (0.1.24) with an open upper bound below 0.2.0. None of these block users, but all of them tax every future change — and several other plans in this directory will be executed by agents who benefit directly from a CLAUDE.md. Cheap, one-time, compounding.

## Current state

- No `.swiftformat`, `.swiftlint.yml`, or `CLAUDE.md` exists (verified at `f2dae47`).
- `.github/workflows/ci.yml` — entire file:

  ```yaml
  name: CI
  on:
    push: { branches: [main] }
    pull_request: { branches: [main] }
  jobs:
    build-and-test:
      runs-on: macos-14
      steps:
        - uses: actions/checkout@v4
        - name: Build
          run: swift build
        - name: Test
          run: swift test
  ```

  (Actual file uses expanded YAML — lines 1-17.) No caching: every CI run re-resolves and rebuilds swift-transformers from scratch.
- `Package.swift:23` — `.package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.12")`; `Package.resolved` pins 0.1.24.
- Verification commands: `swift build` (~1 min warm), `swift test` (119 tests, ~70s).
- Key architecture facts for CLAUDE.md (verified): SwiftPM package with library `AutoSuggestApp` + executable `AutoSuggestRunner` + Xcode app shell in `macos/` (xcodegen, `project.yml`); pipeline = `CGEventInputMonitor` → `AXTextContextProvider` → `PolicyEngine` → `SuggestionOrchestrator` (150ms debounce) → `InferenceEngine` (runtime fallback chain: ollama / llama.cpp / coreml per `config.json` `runtimeOrder`) → `FloatingOverlayRenderer` → `AXTextInsertionEngine` (paste-first insertion); config at `~/Library/Application Support/AutoSuggestApp/config.json`, versioned migrations in `Config/ConfigMigrationManager.swift`; privacy invariants: PII filtering before persistence (`Privacy/PIIFilter.swift`), encrypted personalization store (`Privacy/EncryptedFileStore.swift`), telemetry off by default and content-free.

## Commands you will need

| Purpose   | Command       | Expected on success |
|-----------|---------------|---------------------|
| Build     | `swift build` | exit 0              |
| Tests     | `swift test`  | all pass            |
| Formatter (after step 1) | `swiftformat --lint Sources Tests` | exit 0 |

## Scope

**In scope** (the only files you should modify/create):
- `.swiftformat` (create)
- All files under `Sources/` and `Tests/` (formatter-applied changes ONLY — no manual edits)
- `.github/workflows/ci.yml`
- `Package.swift` (dependency floor only)
- `CLAUDE.md` (create)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch, even though they look related):
- `.github/workflows/release.yml` — plan 008 rewrites it; touching it here creates a conflict.
- `.github/workflows/pages.yml`.
- `website/`, `training/`, `docs/` content.
- Any behavioral code change — if the formatter's output changes semantics (it shouldn't), STOP.

## Git workflow

- Branch: `advisor/007-dx-bundle`
- Commit per step (formatter pass = its own commit so it's trivially reviewable); message style: short imperative summary.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add SwiftFormat config and apply it

Install if needed: `brew install swiftformat` (if brew is unavailable, STOP). Create `.swiftformat` matching the existing style (4-space indent, ~120 col, Swift 6):

```
--swiftversion 6.0
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapcollections before-first
--stripunusedargs closure-only
--self remove
--importgrouping testable-bottom
--disable wrapMultilineStatementBraces, andOperator
```

Run `swiftformat Sources Tests`. Inspect the diff size; commit the result as a standalone commit ("Apply swiftformat").

**Verify**: `swiftformat --lint Sources Tests` → exit 0; `swift build` → exit 0; `swift test` → all pass (count unchanged from before the format).

### Step 2: CI — add caching and a lint job

Rewrite `.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
jobs:
  lint:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install SwiftFormat
        run: brew install swiftformat
      - name: Lint
        run: swiftformat --lint Sources Tests
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Cache SwiftPM
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
          restore-keys: ${{ runner.os }}-spm-
      - name: Build
        run: swift build
      - name: Test
        run: swift test
```

**Verify**: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` → no error (or `actionlint` if installed → exit 0).

### Step 3: Raise the dependency floor

In `Package.swift:23`, change `from: "0.1.12"` → `from: "0.1.24"` and add a trailing comment: `// 0.1.24 verified against this codebase; test before crossing 0.2.0`.

**Verify**: `swift build` → exit 0; `git diff Package.resolved` → empty (already resolved at 0.1.24).

### Step 4: Write CLAUDE.md

Create `CLAUDE.md` at the repo root with exactly these sections, populated from the facts in "Current state" (do not invent — if unsure of a detail, check the cited file):

1. **What this is** — 2 sentences (system-wide macOS autocomplete via local LLMs; SwiftPM lib + runner + xcodegen app shell in `macos/`).
2. **Build / test / lint** — `swift build`, `swift test` (119+ tests, ~70s), `swiftformat --lint Sources Tests`; Xcode app: `cd macos && xcodegen generate`.
3. **Architecture map** — the keystroke→insertion pipeline with one line per stage and its file path (use the chain in "Current state").
4. **Critical paths — extra care** — text insertion (`Suggestions/AXTextInsertionEngine.swift`: can corrupt user text), policy/secure-field suppression (`System/PolicyEngine.swift`, `Context/AXTextContextProvider.swift`: password safety), config migrations (`Config/ConfigMigrationManager.swift`: never break v0/v1 configs), privacy invariants (never log or persist raw typed text/completions — PII-filter before any persistence; telemetry stays content-free).
5. **Conventions** — XCTest with `@testable import AutoSuggestApp`, test files mirror source names (`PolicyEngine` → `PolicyEngineTests`); `Logger(scope:)` wrapper, never `print`; user-facing config changes need a `ConfigMigrationManager` step; UI strings currently hardcoded English.
6. **Gotchas** — real AX/CGEvent behavior untestable in CI (mocks in `IntegrationTestHarness.swift`); permission testing requires the Xcode app target, not the SwiftPM runner; `plans/` contains advisor-generated implementation plans with their own index.

**Verify**: file exists; every file path mentioned in it resolves (`ls` each, or scripted: `grep -oE '[A-Za-z/]+\.swift' CLAUDE.md | sort -u | xargs ls` → no errors).

### Step 5: Full suite

**Verify**: `swift test` → exit 0.

## Test plan

No new tests — this plan is tooling/docs. The full suite plus `swiftformat --lint` are the gates.

## Done criteria

- [ ] `swiftformat --lint Sources Tests` exits 0
- [ ] `.github/workflows/ci.yml` contains an `actions/cache@v4` step and a `lint` job
- [ ] `Package.swift` floor is `0.1.24`
- [ ] `CLAUDE.md` exists, all paths in it resolve
- [ ] `swift test` exits 0, test count unchanged by the format commit
- [ ] `.github/workflows/release.yml` is untouched (`git diff --name-only` does not list it)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:
- The swiftformat diff touches > ~80% of lines in `Sources/` (config too aggressive — report, propose a narrower rule set, wait).
- `swift test` fails after the format pass (formatter changed semantics — revert the format commit and report the offending rule).
- Homebrew/swiftformat unavailable in your environment.
- Plans 001–006 are not yet merged (check `plans/README.md` status) — running the formatter now would conflict with their diffs.

## Maintenance notes

- New contributors: CONTRIBUTING.md should eventually point at `CLAUDE.md`'s build/lint commands (deferred — keep docs single-sourced).
- Reviewer should scrutinize: the formatter commit in isolation (semantics-free), and CLAUDE.md's privacy-invariants wording (it encodes plan 002's policy for future agents).
- The `0.2.0` upper bound is implicit in `from:` — when swift-transformers 0.2 ships, bumping is a deliberate, tested change.
