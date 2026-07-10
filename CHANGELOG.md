# Changelog

## 0.1.0 - 2026-07-10

Initial release.

- Package scaffold: strict analysis options, CI, MIT license, architecture docs.
- Vendored MurmurHash3 x86 32-bit (web-safe 16-bit limb arithmetic), verified
  against published reference vectors.
- `getRolloutBucket(userId, featureKey)`: deterministic 0-99 bucketing via
  `murmur3("userId:featureKey") % 100`, with pinned permanence-guard
  regression vectors.
- Config models (`RemoteConfig`, `FeatureConfig`, `TargetingRules`,
  `UserContext`, `EvaluationResult`) with strict, atomic JSON validation:
  schema violations throw `ConfigValidationException` with the offending
  JSON path and are never partially applied. Round-trip `toJson` support
  for Last-Known-Good caching.
- `evaluateFlag`: pure, synchronous evaluation walking the strict hierarchy
  kill-switch > targeting (numeric per-component `minAppVersion`,
  case-insensitive `allowedCountries`, AND semantics, safe-default exclusion
  on missing attributes) > percentage rollout (0/100 short-circuit) >
  fallback, every decision explained via `EvaluationResult`.
- `ConfigSessionController` with selective freeze: boots on compiled-in
  defaults, hydrates from the Last-Known-Good cache, persists fresh fetches
  for the next launch while freezing non-emergency changes mid-session, and
  applies kill-switch activations live (monotonic within a session) with
  change notifications. Abstract `ConfigFetcher`/`ConfigStore` interfaces
  keep the package free of network and storage dependencies.
