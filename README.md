# feature_flag_kit

[![CI](https://github.com/Dakshita0310/feature_flag_kit/actions/workflows/ci.yaml/badge.svg)](https://github.com/Dakshita0310/feature_flag_kit/actions/workflows/ci.yaml)
[![pub package](https://img.shields.io/pub/v/feature_flag_kit.svg)](https://pub.dev/packages/feature_flag_kit)

A platform-agnostic feature flag and staged-rollout evaluation engine for
Dart: deterministic bucketing, instant kill-switches, targeting rules, and
explainable results. Zero runtime dependencies.

## Design principles

- **Deterministic:** users are assigned to rollout buckets via MurmurHash3 of
  `userId:featureKey`, so exposure is stable across sessions and devices, and
  independent per feature (no sticky cohorts).
- **Explainable:** every evaluation returns an `EvaluationResult` with a
  reason code and debug message, never a bare boolean.
- **Strict hierarchy:** kill-switch > targeting rules > percentage rollout >
  fallback default.
- **Session-stable:** non-emergency config changes are frozen for the current
  session; only kill-switch activations apply live (selective freeze).
- **Zero runtime dependencies:** pure Dart, no Flutter or network coupling.
  Fetching and persistence are abstract interfaces implemented by the host.

## Quick start: pure evaluation

```dart
import 'package:feature_flag_kit/feature_flag_kit.dart';

final config = RemoteConfig.parse(rawJsonFromYourBackend);
final user = UserContext(userId: 'user_a', country: 'US', appVersion: '2.1.0');

final result = evaluateFlag(
  featureKey: 'new_checkout',
  user: user,
  config: config,
);

if (result.isEnabled) {
  // show the feature
}
print(result.debugMessage);
// e.g. "User 'user_a' hashed to bucket 10; feature 'new_checkout' rollout
//       is 50%. Result: ENABLED."
```

Evaluation is synchronous, in-memory, and free of I/O, clock reads, and
randomness: the same inputs always produce the same decision.

## Session management: `ConfigSessionController`

For long-lived apps, wrap the engine in the controller, which implements the
boot/refresh lifecycle with **selective freeze** semantics:

1. **Boot instantly** on compiled-in defaults, then hydrate from the
   Last-Known-Good cache via your `ConfigStore`.
2. **Refresh on your triggers** (cold start, app foregrounding, silent-push
   wake) via your `ConfigFetcher`. Fresh configs are validated and persisted
   for the next launch.
3. **Freeze non-emergency changes** mid-session, so rollout percentages and
   targeting changes never shift the UI while a user is interacting with it.
4. **Apply kill-switches live**: an activated kill-switch tears the feature
   down mid-session and emits on `changes` for reactive UIs.

```dart
final controller = ConfigSessionController(
  defaults: myBakedInDefaults,
  fetcher: MyHttpConfigFetcher(),   // implements ConfigFetcher
  store: MySharedPrefsStore(),      // implements ConfigStore
  user: UserContext(userId: currentUserId),
);

await controller.initialize();      // hydrate from LKG cache
unawaited(controller.refresh());    // background fetch, never throws

controller.changes.listen((_) {
  // re-render gated UI: a live kill-switch arrived or the user switched
});

if (controller.isEnabled('new_checkout')) {
  // one-line gating for UI code
}
controller.evaluate('new_checkout'); // rich result for debug menus/telemetry
```

Malformed or truncated payloads are rejected atomically with
`ConfigValidationException` (never partially applied), corrupted caches fall
back to defaults, and kill-switch application never depends on disk health.

## Config schema

```json
{
  "version": "v1",
  "features": {
    "new_checkout": {
      "isKillSwitchActive": false,
      "rolloutPercentage": 50,
      "targeting": {
        "minAppVersion": "2.1.0",
        "allowedCountries": ["US", "CA"]
      }
    }
  }
}
```

`targeting` is optional; rules use AND semantics, versions compare
numerically per component (`2.10.0 > 2.9.0`), and countries match
case-insensitively. If a rule is present but the user attribute is unknown,
the user is excluded (safe default).

## Determinism contract

Buckets are `murmur3_x86_32(utf8("userId:featureKey")) % 100`, using the
same MurmurHash3 variant as LaunchDarkly, Unleash, and GrowthBook. The
implementation is vendored, verified against published reference vectors,
and pinned by regression tests, because this mapping is permanent: changing
it would silently reassign every user's bucket.

## Architecture

See [doc/engine_architecture_spec.md](doc/engine_architecture_spec.md).

## License

MIT
