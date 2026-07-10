import 'dart:async';

import 'package:feature_flag_kit/feature_flag_kit.dart';
import 'package:test/test.dart';

// Pinned buckets (see bucketing_test.dart permanence guard):
//   user_a : new_checkout -> 10 (inside 50%)
//   user_b : new_checkout -> 82 (outside 50%)

RemoteConfig config(
  String version, {
  bool killSwitch = false,
  int rollout = 50,
}) =>
    RemoteConfig(version: version, features: {
      'new_checkout': FeatureConfig(
        isKillSwitchActive: killSwitch,
        rolloutPercentage: rollout,
      ),
    });

class FakeFetcher implements ConfigFetcher {
  FakeFetcher(this._results);
  final List<Object> _results; // RemoteConfig to return or Exception to throw
  var fetchCount = 0;

  @override
  Future<RemoteConfig> fetch() async {
    fetchCount++;
    final next = _results.removeAt(0);
    if (next is RemoteConfig) return next;
    throw next as Exception;
  }
}

class FakeStore implements ConfigStore {
  FakeStore({this.preloaded, this.loadError, this.saveError});
  RemoteConfig? preloaded;
  Exception? loadError;
  Exception? saveError;
  final saved = <RemoteConfig>[];

  @override
  Future<RemoteConfig?> load() async {
    if (loadError != null) throw loadError!;
    return preloaded;
  }

  @override
  Future<void> save(RemoteConfig config) async {
    if (saveError != null) throw saveError!;
    saved.add(config);
    preloaded = config; // subsequent loads see the LKG, like a real disk
  }
}

ConfigSessionController controller({
  ConfigFetcher? fetcher,
  ConfigStore? store,
  RemoteConfig? defaults,
  String userId = 'user_a',
}) =>
    ConfigSessionController(
      defaults: defaults ?? config('defaults'),
      fetcher: fetcher ?? FakeFetcher([]),
      store: store ?? FakeStore(),
      user: UserContext(userId: userId),
    );

void main() {
  group('boot hydration', () {
    test('with no cache, evaluates against baked-in defaults', () async {
      final c = controller(defaults: config('defaults', rollout: 50));
      await c.initialize();

      expect(c.sessionConfigVersion, 'defaults');
      // user_a is bucket 10, inside 50%.
      expect(c.isEnabled('new_checkout'), isTrue);
    });

    test('with a cached LKG config, hydrates from it instead of defaults',
        () async {
      final c = controller(
        defaults: config('defaults', rollout: 50),
        store: FakeStore(preloaded: config('lkg', rollout: 5)),
      );
      await c.initialize();

      expect(c.sessionConfigVersion, 'lkg');
      // bucket 10 is outside 5%.
      expect(c.isEnabled('new_checkout'), isFalse);
    });

    test('with a corrupted cache, falls back to defaults without crashing',
        () async {
      final c = controller(
        defaults: config('defaults', rollout: 50),
        store: FakeStore(
          loadError: ConfigValidationException(r'$', 'corrupted'),
        ),
      );
      await c.initialize();

      expect(c.sessionConfigVersion, 'defaults');
      expect(c.isEnabled('new_checkout'), isTrue);
    });
  });

  group('selective freeze', () {
    test('rollout changes are persisted but frozen for the session', () async {
      final store = FakeStore();
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', rollout: 100)]),
        store: store,
        userId: 'user_b', // bucket 82: outside 50%, inside 100%
      );
      await c.initialize();
      await c.refresh();

      // Persisted for next launch...
      expect(store.saved.single.version, 'v2');
      expect(c.latestFetchedVersion, 'v2');
      // ...but the session still evaluates against v1.
      expect(c.sessionConfigVersion, 'v1');
      expect(c.isEnabled('new_checkout'), isFalse);
    });

    test('a restart after refresh applies the frozen changes (next launch)',
        () async {
      final store = FakeStore();
      final first = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', rollout: 100)]),
        store: store,
        userId: 'user_b',
      );
      await first.initialize();
      await first.refresh();
      expect(first.isEnabled('new_checkout'), isFalse);

      // Simulated cold start: a new controller over the same store.
      final second = controller(
        defaults: config('v1', rollout: 50),
        store: store,
        userId: 'user_b',
      );
      await second.initialize();
      expect(second.sessionConfigVersion, 'v2');
      expect(second.isEnabled('new_checkout'), isTrue);
    });

    test('kill-switch activation applies live mid-session', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', killSwitch: true)]),
      );
      await c.initialize();
      expect(c.isEnabled('new_checkout'), isTrue);

      await c.refresh();

      expect(c.isEnabled('new_checkout'), isFalse);
      expect(c.evaluate('new_checkout').reason, EvaluationReason.killSwitch);
      // The rest of the fresh config stays frozen.
      expect(c.sessionConfigVersion, 'v1');
    });

    test('kill-switch release stays disabled until next launch', () async {
      final c = controller(
        defaults: config('v1', killSwitch: true),
        fetcher: FakeFetcher([config('v2', killSwitch: false)]),
      );
      await c.initialize();
      await c.refresh();

      // Re-enabling mid-session would be a UI shift; freeze applies.
      expect(c.isEnabled('new_checkout'), isFalse);
      expect(c.evaluate('new_checkout').reason, EvaluationReason.killSwitch);
    });

    test('kill-switch still applies when persisting the LKG fails', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', killSwitch: true)]),
        store: FakeStore(saveError: Exception('disk full')),
      );
      await c.initialize();
      await c.refresh();

      expect(c.isEnabled('new_checkout'), isFalse);
    });
  });

  group('refresh failure modes', () {
    test('a network error leaves the session state untouched', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([Exception('socket closed')]),
      );
      await c.initialize();
      await c.refresh();

      expect(c.sessionConfigVersion, 'v1');
      expect(c.isEnabled('new_checkout'), isTrue);
      expect(c.lastRefreshError, isNotNull);
    });

    test('an invalid payload is discarded and the LKG kept', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([
          ConfigValidationException('features', 'truncated payload'),
        ]),
      );
      await c.initialize();
      await c.refresh();

      expect(c.sessionConfigVersion, 'v1');
      expect(c.isEnabled('new_checkout'), isTrue);
      expect(c.lastRefreshError, isA<ConfigValidationException>());
    });

    test('a successful refresh clears the previous error', () async {
      final c = controller(
        defaults: config('v1'),
        fetcher: FakeFetcher([Exception('offline'), config('v2')]),
      );
      await c.initialize();
      await c.refresh();
      expect(c.lastRefreshError, isNotNull);

      await c.refresh();
      expect(c.lastRefreshError, isNull);
    });
  });

  group('user context switching', () {
    test('changing users re-evaluates buckets immediately', () async {
      final c = controller(defaults: config('v1', rollout: 50));
      await c.initialize();
      expect(c.isEnabled('new_checkout'), isTrue); // user_a, bucket 10

      c.updateUserContext(UserContext(userId: 'user_b')); // bucket 82
      expect(c.isEnabled('new_checkout'), isFalse);
    });
  });

  group('change notifications', () {
    test('kill-switch activation emits a change event', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', killSwitch: true)]),
      );
      await c.initialize();

      final events = <void>[];
      final sub = c.changes.listen(events.add);
      await c.refresh();
      await pumpEventQueue();

      expect(events, hasLength(1));
      await sub.cancel();
    });

    test('a frozen-only refresh does not emit', () async {
      final c = controller(
        defaults: config('v1', rollout: 50),
        fetcher: FakeFetcher([config('v2', rollout: 100)]),
      );
      await c.initialize();

      final events = <void>[];
      final sub = c.changes.listen(events.add);
      await c.refresh();
      await pumpEventQueue();

      expect(events, isEmpty);
      await sub.cancel();
    });

    test('updateUserContext emits a change event', () async {
      final c = controller(defaults: config('v1'));
      await c.initialize();

      final events = <void>[];
      final sub = c.changes.listen(events.add);
      c.updateUserContext(UserContext(userId: 'user_b'));
      await pumpEventQueue();

      expect(events, hasLength(1));
      await sub.cancel();
    });
  });

  group('evaluation memoization', () {
    test('repeated evaluations return consistent results', () async {
      final c = controller(defaults: config('v1', rollout: 50));
      await c.initialize();

      final first = c.evaluate('new_checkout');
      for (var i = 0; i < 100; i++) {
        expect(c.evaluate('new_checkout'), first);
      }
    });
  });
}
