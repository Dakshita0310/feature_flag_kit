import '../models/remote_config.dart';

/// Source of fresh config payloads.
///
/// Implemented by the host application: an HTTP client in production, a mock
/// repository in demos and tests. Implementations should validate raw
/// payloads via [RemoteConfig.parse] so corruption surfaces as
/// [ConfigValidationException] and is never applied.
///
/// The engine is transport-agnostic: cold starts, app foregrounding, and
/// silent-push wakes all funnel into the same fetch path.
abstract interface class ConfigFetcher {
  /// Fetches, validates, and returns the latest remote config.
  Future<RemoteConfig> fetch();
}

/// Persistence for the Last-Known-Good (LKG) config.
///
/// Implemented by the host application (e.g. SharedPreferences on Flutter,
/// a file on server-side Dart). [load] should throw
/// [ConfigValidationException] for corrupted payloads so the controller can
/// fall back to compiled-in defaults.
abstract interface class ConfigStore {
  /// Loads the cached config, or null when no cache exists.
  Future<RemoteConfig?> load();

  /// Persists [config] as the new Last-Known-Good payload.
  Future<void> save(RemoteConfig config);
}
