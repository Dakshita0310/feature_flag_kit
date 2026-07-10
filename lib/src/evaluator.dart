import 'bucketing.dart';
import 'models/evaluation_result.dart';
import 'models/remote_config.dart';
import 'models/user_context.dart';

/// Evaluates [featureKey] for [user] against [config], walking the strict
/// hierarchy: kill-switch > targeting rules > percentage rollout > fallback.
///
/// Pure and synchronous: no I/O, no clock reads, no randomness. The same
/// inputs always produce the same result, which is what makes rollouts
/// deterministic and explainable.
///
/// Targeting uses safe defaults: if a rule is present but the corresponding
/// [UserContext] attribute is unknown, the user is excluded rather than
/// included.
EvaluationResult evaluateFlag({
  required String featureKey,
  required UserContext user,
  required RemoteConfig config,
}) {
  // 0. Fallback: feature absent from the config.
  final feature = config.features[featureKey];
  if (feature == null) {
    return EvaluationResult(
      isEnabled: false,
      reason: EvaluationReason.fallback,
      debugMessage: "Feature '$featureKey' is missing from config "
          '${config.version}; the baked-in default applies.',
    );
  }

  // 1. Kill-switch: global emergency override.
  if (feature.isKillSwitchActive) {
    return EvaluationResult(
      isEnabled: false,
      reason: EvaluationReason.killSwitch,
      debugMessage: "Feature '$featureKey' is disabled by its kill-switch.",
    );
  }

  // 2. Targeting rules.
  final targeting = feature.targeting;
  if (targeting != null) {
    final miss = _matchTargeting(user, targeting);
    if (miss != null) {
      return EvaluationResult(
        isEnabled: false,
        reason: EvaluationReason.targetingMiss,
        debugMessage: "Feature '$featureKey': $miss",
      );
    }
  }

  // 3. Percentage rollout. 0 and 100 short-circuit without hashing.
  final percentage = feature.rolloutPercentage;
  if (percentage == 100) {
    return EvaluationResult(
      isEnabled: true,
      reason: EvaluationReason.rolloutHit,
      debugMessage: "Feature '$featureKey' is rolled out to 100%.",
    );
  }
  if (percentage == 0) {
    return EvaluationResult(
      isEnabled: false,
      reason: EvaluationReason.rolloutMiss,
      debugMessage: "Feature '$featureKey' is rolled out to 0%.",
    );
  }

  final bucket = getRolloutBucket(user.userId, featureKey);
  final isEnabled = bucket < percentage;
  return EvaluationResult(
    isEnabled: isEnabled,
    reason:
        isEnabled ? EvaluationReason.rolloutHit : EvaluationReason.rolloutMiss,
    debugMessage: "User '${user.userId}' hashed to bucket $bucket; "
        "feature '$featureKey' rollout is $percentage%. "
        'Result: ${isEnabled ? 'ENABLED' : 'DISABLED'}.',
  );
}

/// Returns null when [user] matches all rules, or a human-readable
/// description of the first failing rule.
String? _matchTargeting(UserContext user, TargetingRules targeting) {
  final minVersion = targeting.minAppVersion;
  if (minVersion != null) {
    final userVersion = user.appVersion;
    if (userVersion == null) {
      return 'targeting requires appVersion >= $minVersion but the user '
          'context has no appVersion.';
    }
    if (_compareVersions(userVersion, minVersion) < 0) {
      return 'targeting requires appVersion >= $minVersion but the user is '
          'on $userVersion.';
    }
  }

  final allowedCountries = targeting.allowedCountries;
  if (allowedCountries != null) {
    final country = user.country;
    if (country == null) {
      return 'targeting requires country in $allowedCountries but the user '
          'context has no country.';
    }
    final normalized = country.toUpperCase();
    final allowed = allowedCountries.any((c) => c.toUpperCase() == normalized);
    if (!allowed) {
      return 'targeting requires country in $allowedCountries but the user '
          'is in $country.';
    }
  }

  return null;
}

/// Compares dot-separated numeric versions component-wise; missing
/// components count as zero (so `2.1` == `2.1.0`).
int _compareVersions(String a, String b) {
  final aParts = a.split('.');
  final bParts = b.split('.');
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final aValue = i < aParts.length ? int.parse(aParts[i]) : 0;
    final bValue = i < bParts.length ? int.parse(bParts[i]) : 0;
    if (aValue != bValue) return aValue - bValue;
  }
  return 0;
}
