/// Identity and targeting attributes for the user being evaluated.
///
/// The [userId] seeds deterministic bucketing, so changing it (e.g. on
/// login/logout) changes every rollout bucket for this user. The optional
/// attributes are consumed by targeting rules.
class UserContext {
  /// Creates a user context.
  ///
  /// Throws [ArgumentError] if [userId] is empty: an empty id would silently
  /// collapse all users into one bucket per feature.
  UserContext({required this.userId, this.country, this.appVersion}) {
    if (userId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'must not be empty');
    }
  }

  /// Stable identifier used as the bucketing hash seed.
  final String userId;

  /// ISO country code used by `allowedCountries` targeting, if known.
  final String? country;

  /// Application version used by `minAppVersion` targeting, if known.
  final String? appVersion;

  @override
  bool operator ==(Object other) =>
      other is UserContext &&
      other.userId == userId &&
      other.country == country &&
      other.appVersion == appVersion;

  @override
  int get hashCode => Object.hash(userId, country, appVersion);

  @override
  String toString() =>
      'UserContext(userId: $userId, country: $country, appVersion: $appVersion)';
}
