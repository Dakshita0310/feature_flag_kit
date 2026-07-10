# feature_flag_kit

A platform-agnostic feature flag and staged-rollout evaluation engine for Dart.

> Status: under active development. Not yet published.

## Design principles

- **Deterministic:** users are assigned to rollout buckets via MurmurHash3 of
  `userId:featureKey`, so exposure is stable across sessions and devices, and
  independent per feature (no sticky cohorts).
- **Explainable:** every evaluation returns an `EvaluationResult` with a reason
  code and debug message, never a bare boolean.
- **Strict hierarchy:** kill-switch > targeting rules > percentage rollout >
  fallback default.
- **Session-stable:** non-emergency config changes are frozen for the current
  session; only kill-switch transitions apply live (selective freeze).
- **Zero runtime dependencies:** pure Dart, no Flutter or network coupling.
  Storage and fetching are abstract interfaces implemented by the host app.

## Architecture

See [docs/engine_architecture_spec.md](docs/engine_architecture_spec.md).

## Roadmap

- [x] Package scaffold, CI, strict lints
- [x] Vendored MurmurHash3 + deterministic bucketing
- [x] Config models + strict validation
- [ ] Evaluation hierarchy with explainability
- [ ] Session controller (selective freeze) + v0.1.0 release

## License

MIT
