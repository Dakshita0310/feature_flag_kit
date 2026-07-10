import 'dart:async';

import '../evaluator.dart';
import '../models/evaluation_result.dart';
import '../models/remote_config.dart';
import '../models/user_context.dart';
import 'interfaces.dart';

/// Orchestrates config state for one app session with selective freeze
/// semantics.
///
/// Lifecycle:
///
/// 1. Construct with compiled-in [defaults]; evaluation works immediately.
/// 2. [initialize] hydrates the session config from the [ConfigStore]'s
///    Last-Known-Good cache (falling back to defaults if absent/corrupted).
/// 3. The host calls [refresh] on its triggers (cold start, foregrounding,
///    silent push). Fresh configs are validated and persisted for the next
///    launch, but non-emergency changes are frozen for the current session
///    to prevent mid-session UI shifts.
/// 4. Kill-switch activations in a fresh config apply immediately: the
///    feature is torn down mid-session and a [changes] event is emitted.
///
/// Kill-switch overrides are monotonic within a session: once a feature is
/// killed it stays disabled until the next launch, even if a later fetch
/// releases the switch, because re-enabling mid-session is itself a UI shift.
class ConfigSessionController {
  /// Creates a controller that boots on [defaults] and evaluates for [user].
  ConfigSessionController({
    required RemoteConfig defaults,
    required ConfigFetcher fetcher,
    required ConfigStore store,
    required UserContext user,
  })  : _sessionConfig = defaults,
        _fetcher = fetcher,
        _store = store,
        _user = user;

  final ConfigFetcher _fetcher;
  final ConfigStore _store;

  RemoteConfig _sessionConfig;
  RemoteConfig? _latestFetched;
  Set<String> _liveKillSwitches = const {};
  Object? _lastRefreshError;
  UserContext _user;

  final Map<String, EvaluationResult> _memo = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Emits whenever an evaluation outcome may have changed mid-session
  /// (a live kill-switch arrived or the user context switched).
  ///
  /// Frozen changes do not emit: they only take effect on the next launch.
  Stream<void> get changes => _changes.stream;

  /// Version of the config the current session evaluates against.
  String get sessionConfigVersion => _sessionConfig.version;

  /// Version of the most recently fetched config (persisted for next
  /// launch), or null if no fetch has succeeded this session.
  String? get latestFetchedVersion => _latestFetched?.version;

  /// The error from the most recent [refresh], or null if it succeeded.
  Object? get lastRefreshError => _lastRefreshError;

  /// The user context evaluations currently run against.
  UserContext get currentUser => _user;

  /// Features disabled by a live kill-switch received this session.
  Set<String> get activeKillSwitches => Set.unmodifiable(_liveKillSwitches);

  /// Hydrates the session config from the Last-Known-Good cache.
  ///
  /// Call once at boot, before the first frame if possible. Absent or
  /// corrupted caches leave the compiled-in defaults in place; this never
  /// throws.
  Future<void> initialize() async {
    try {
      final cached = await _store.load();
      if (cached != null) {
        _sessionConfig = cached;
        _memo.clear();
      }
    } on Exception {
      // Corrupted or unreadable cache: stay on compiled-in defaults.
    }
  }

  /// Fetches the latest config and applies selective freeze semantics.
  ///
  /// On success the payload is persisted as the Last-Known-Good for the
  /// next launch; newly activated kill-switches apply immediately and emit
  /// on [changes]. On failure ([lastRefreshError]) the session state is
  /// left untouched. Never throws: triggers can fire-and-forget.
  Future<void> refresh() async {
    RemoteConfig fresh;
    try {
      fresh = await _fetcher.fetch();
    } on Exception catch (error) {
      _lastRefreshError = error;
      return;
    }
    _lastRefreshError = null;
    _latestFetched = fresh;

    try {
      await _store.save(fresh);
    } on Exception {
      // Kill-switch safety must not depend on disk health; the fetched
      // config simply won't be the LKG on next launch.
    }

    final freshKills = <String>{
      for (final entry in fresh.features.entries)
        if (entry.value.isKillSwitchActive) entry.key,
    };
    final added = freshKills.difference(_liveKillSwitches);
    if (added.isNotEmpty) {
      _liveKillSwitches = {..._liveKillSwitches, ...added};
      _memo.clear();
      _changes.add(null);
    }
  }

  /// Evaluates [featureKey] against the frozen session config merged with
  /// live kill-switch overrides. Synchronous, in-memory, memoized.
  EvaluationResult evaluate(String featureKey) {
    return _memo.putIfAbsent(featureKey, () {
      if (_liveKillSwitches.contains(featureKey)) {
        return EvaluationResult(
          isEnabled: false,
          reason: EvaluationReason.killSwitch,
          debugMessage: "Feature '$featureKey' was disabled mid-session by a "
              'live kill-switch (config ${_latestFetched?.version}).',
        );
      }
      return evaluateFlag(
        featureKey: featureKey,
        user: _user,
        config: _sessionConfig,
      );
    });
  }

  /// Frictionless boolean check for UI gating; strips the metadata that
  /// [evaluate] carries.
  bool isEnabled(String featureKey) => evaluate(featureKey).isEnabled;

  /// Switches the evaluated user (e.g. login/logout), flushing memoized
  /// results and emitting a [changes] event, since every bucket changes
  /// with the userId.
  void updateUserContext(UserContext newContext) {
    if (newContext == _user) return;
    _user = newContext;
    _memo.clear();
    _changes.add(null);
  }

  /// Releases the [changes] stream. Call when the host is done with the
  /// controller.
  Future<void> dispose() => _changes.close();
}
