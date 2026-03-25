# Contributing to Autosuggest

## Build

**Command line:**

```bash
swift build
```

**Xcode:**

```bash
cd macos && xcodegen generate
```

Then open the generated `.xcodeproj` in Xcode.

## Test

```bash
swift test
```

## Code Style

- Swift 6.2 with strict concurrency enabled.
- Use `@MainActor` for all UI and accessibility code.
- Use actors for shared mutable state.
- All types crossing concurrency boundaries must conform to `Sendable`.
- No force unwraps (`!`) or force casts (`as!`).

## PR Process

1. Fork the repository.
2. Create a branch from `main`.
3. Make your changes and ensure `swift build` and `swift test` pass.
4. Open a pull request with a clear description of what changed and why.

## Adding a New Runtime

1. Create a type that conforms to the `InferenceRuntime` protocol.
2. Register it in `InferenceRuntimeFactory`.
3. Add its identifier to `knownRuntimes` in `ConfigValidator`.

## Adding Exclusion Rules

1. Add the necessary fields to `ExclusionRule`.
2. Update `PolicyEngine.isExcludedByUserRule` to evaluate the new fields.

## License

This project is licensed under the GNU General Public License v3.0. All contributions must be compatible with GPL v3.
