# Changelog

## 0.1.0 (unreleased)

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
