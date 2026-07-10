// ignore_for_file: avoid_print

import 'package:feature_flag_kit/feature_flag_kit.dart';

/// In-memory stand-ins for the host-provided network and disk layers.
class DemoFetcher implements ConfigFetcher {
  RemoteConfig next = RemoteConfig.parse('''
  {
    "version": "v2-remote",
    "features": {
      "new_checkout": {"isKillSwitchActive": true, "rolloutPercentage": 50}
    }
  }
  ''');

  @override
  Future<RemoteConfig> fetch() async => next;
}

class DemoStore implements ConfigStore {
  RemoteConfig? _cache;

  @override
  Future<RemoteConfig?> load() async => _cache;

  @override
  Future<void> save(RemoteConfig config) async => _cache = config;
}

Future<void> main() async {
  // 1. Pure evaluation: deterministic, synchronous, explainable.
  final config = RemoteConfig.parse('''
  {
    "version": "v1",
    "features": {
      "new_checkout": {
        "isKillSwitchActive": false,
        "rolloutPercentage": 50,
        "targeting": {"minAppVersion": "2.0.0", "allowedCountries": ["US"]}
      }
    }
  }
  ''');

  final user =
      UserContext(userId: 'user_a', country: 'US', appVersion: '2.1.0');
  final result = evaluateFlag(
    featureKey: 'new_checkout',
    user: user,
    config: config,
  );
  print('${result.isEnabled} (${result.reason}): ${result.debugMessage}');

  // 2. Session controller: boot on defaults, refresh, selective freeze.
  final controller = ConfigSessionController(
    defaults: config,
    fetcher: DemoFetcher(),
    store: DemoStore(),
    user: user,
  );
  await controller.initialize();
  print('booted: new_checkout=${controller.isEnabled('new_checkout')}');

  controller.changes.listen((_) {
    print('live change! new_checkout=${controller.isEnabled('new_checkout')}');
  });

  // The fetched config activates a kill-switch: it applies mid-session.
  await controller.refresh();
  print(controller.evaluate('new_checkout').debugMessage);

  await controller.dispose();
}
