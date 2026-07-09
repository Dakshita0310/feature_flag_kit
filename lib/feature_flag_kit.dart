/// A platform-agnostic feature flag and staged-rollout evaluation engine.
///
/// Provides deterministic MurmurHash3-based percentage bucketing, a strict
/// evaluation hierarchy (kill-switch > targeting > rollout > fallback),
/// explainable evaluation results, and a session controller implementing
/// selective freeze semantics.
///
/// This package has zero runtime dependencies. Config fetching and local
/// persistence are abstract interfaces implemented by the host application.
library;

export 'src/bucketing.dart';
