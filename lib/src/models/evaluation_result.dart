/// Why an evaluation produced its decision.
enum EvaluationReason {
  /// The feature is globally disabled by its kill-switch.
  killSwitch,

  /// The user did not match the feature's targeting rules.
  targetingMiss,

  /// The user's deterministic bucket falls inside the rollout percentage.
  rolloutHit,

  /// The user's deterministic bucket falls outside the rollout percentage.
  rolloutMiss,

  /// The feature is missing from the config; the baked-in default applies.
  fallback,
}

/// The rich result of evaluating a feature flag.
///
/// The engine never returns a bare boolean: every decision carries the
/// [reason] it was made and a human-readable [debugMessage] for developer
/// menus and exposure logging.
class EvaluationResult {
  /// Creates an evaluation result.
  const EvaluationResult({
    required this.isEnabled,
    required this.reason,
    required this.debugMessage,
  });

  /// Whether the feature is enabled for the evaluated user.
  final bool isEnabled;

  /// The hierarchy step that decided the outcome.
  final EvaluationReason reason;

  /// Human-readable explanation of the decision (bucket, rule, percentage).
  final String debugMessage;

  @override
  bool operator ==(Object other) =>
      other is EvaluationResult &&
      other.isEnabled == isEnabled &&
      other.reason == reason &&
      other.debugMessage == debugMessage;

  @override
  int get hashCode => Object.hash(isEnabled, reason, debugMessage);

  @override
  String toString() =>
      'EvaluationResult(isEnabled: $isEnabled, reason: $reason, '
      'debugMessage: $debugMessage)';
}
