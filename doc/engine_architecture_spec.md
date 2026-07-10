# Architectural Specification: Core Evaluation Engine (feature_flag_kit)

## Overview

This document specifies the design of `feature_flag_kit`, a platform-agnostic
feature flag and staged-rollout evaluation engine for Dart. The engine
guarantees deterministic exposure, a strict evaluation hierarchy (including
emergency kill-switches), session-stable configuration semantics, and rich
debugging output.

The package ships with zero runtime dependencies. It contains no Flutter,
network, or storage code: config fetching and local persistence are abstract
interfaces (`ConfigFetcher`, `ConfigStore`) implemented by the host
application.

---

## 1. Deterministic Targeting Engine

### The problem with random assignment

If a 20% rollout is decided with a random number at evaluation time, a user
might see a feature on one launch and lose it on the next, or see it on their
phone but not their tablet. This destroys user trust and corrupts A/B
telemetry. Assignment must be stable across time and devices.

### Hashing + modulo (finalized decision)

- **Algorithm:** MurmurHash3, x86 32-bit variant, vendored into the package as
  a reference implementation verified against published test vectors. This is
  the same algorithm used by LaunchDarkly, Unleash, GrowthBook, and Flagsmith.
  No third-party dependency.
- **Payload:** `"$userId:$featureKey"`. The colon separator prevents
  concatenation collisions (e.g. `user1` + `2foo` vs `user12` + `foo`).
  Including the feature key avoids sticky cohorts, where the same users would
  land in the early bucket of every feature simultaneously.
- **Bucket:** `murmur3_x86_32(payload) % 100`, yielding 0-99. A user is in the
  rollout when `bucket < rolloutPercentage`.
- **Permanence:** this choice is permanent. Changing the algorithm, seed, or
  payload format reshuffles every user's bucket. Known payload/bucket pairs
  are pinned as regression tests; if those tests ever fail, determinism has
  been broken and the change must not ship.

```dart
int getRolloutBucket(String userId, String featureKey) {
  final payload = '$userId:$featureKey';
  return murmur3X86_32(utf8.encode(payload)) % 100;
}
```

---

## 2. The Evaluation Hierarchy

Feature flags are evaluated top-down. Emergency constraints override
targeting, and targeting overrides percentage rollouts.

1. **Kill-switch (global override):** if `isKillSwitchActive` is true,
   evaluation stops immediately. Returns disabled.
2. **Targeting rules:** if rules exist (e.g. `minAppVersion`,
   `allowedCountries`) and the user does not match, the user is excluded.
3. **Percentage rollout:** the user's deterministic bucket is compared to the
   rollout percentage.
4. **Default/fallback:** if the config is missing or malformed, return the
   hardcoded default.

### JSON config schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "version": { "type": "string" },
    "features": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "properties": {
          "isKillSwitchActive": {
            "type": "boolean",
            "description": "If true, immediately disables the feature."
          },
          "rolloutPercentage": {
            "type": "integer",
            "minimum": 0,
            "maximum": 100
          },
          "targeting": {
            "type": "object",
            "properties": {
              "minAppVersion": { "type": "string" },
              "allowedCountries": { "type": "array", "items": { "type": "string" } }
            }
          }
        },
        "required": ["isKillSwitchActive", "rolloutPercentage"]
      }
    }
  }
}
```

### Validation semantics

Parsing is strict and atomic. A payload that is truncated, malformed, or
schema-invalid is rejected with a typed error and never partially applied.
The host falls back to the Last-Known-Good cached config, or to compiled-in
defaults if no cache exists.

---

## 3. Session Stability: Selective Freeze (finalized decision)

Three strategies were evaluated:

- **Blocking fetch:** freshest config, but the app hangs on splash waiting for
  the network. Rejected.
- **Async fetch, apply next launch:** instant boot, but a kill-switch flipped
  mid-session is not honored until relaunch. Rejected alone.
- **Selective freeze (chosen):** build on async-with-cache, but split the
  streams by criticality.

The chosen semantics:

1. **Synchronous boot:** the engine initializes from the LKG cached config via
   `ConfigStore`, or compiled-in defaults if no cache exists. Zero latency.
2. **Background fetch:** the host triggers `refresh()` (cold start,
   foregrounding, or a silent-push wake). The engine pulls via
   `ConfigFetcher`, validates, and persists to `ConfigStore`.
3. **Freeze non-emergency changes:** rollout percentages and targeting rules
   from the fresh config are saved for the next launch but frozen for the
   current session, preventing mid-session UI layout shifts.
4. **Apply kill-switches live:** if `isKillSwitchActive` transitions to true
   in the fresh config, the engine applies it immediately and emits a change
   event so a reactive UI can tear the feature down mid-session.

The engine encapsulates this in a `ConfigSessionController`, which holds the
frozen session snapshot plus the live kill-switch overlay, exposes evaluation
against the merged view, and broadcasts change events. `updateUserContext`
(e.g. login/logout) flushes evaluation memoization and re-broadcasts, since a
changed userId changes every bucket.

### Config propagation model (host responsibility)

Pull-based fetching (cold start + app foregrounding) backed by CDNs is the
standard operation. Instant kill-switch latency is achieved by silent push
notifications (APNs/FCM) waking the app to execute the same pull. The engine
is transport-agnostic: all triggers funnel into the single `refresh()` path.

---

## 4. Explainability & Debugging

The engine never returns a bare boolean from its core evaluation. Every
evaluation produces an `EvaluationResult`:

```dart
enum EvaluationReason {
  killSwitch,
  targetingMiss,
  rolloutHit,
  rolloutMiss,
  fallback,
}

class EvaluationResult {
  final bool isEnabled;
  final EvaluationReason reason;
  final String debugMessage;
}
```

Decision tree:

1. Feature missing from config -> `fallback`, disabled, with the feature key
   named in the debug message.
2. Kill-switch active -> `killSwitch`, disabled.
3. Targeting rules present and unmatched -> `targetingMiss`, disabled, with
   the failing rule serialized in the debug message.
4. Rollout 100% -> `rolloutHit`; rollout 0% -> `rolloutMiss` (short-circuits,
   no hashing).
5. Otherwise compare the deterministic bucket to the rollout percentage and
   report the bucket, percentage, and outcome in the debug message.

Host applications expose two calls: a frictionless `isEnabled(key)` that
strips metadata for UI checks, and `evaluate(key)` returning the full
`EvaluationResult` for developer menus and exposure logging.
