import 'dart:convert';

/// Thrown when a config payload fails strict schema validation.
///
/// Validation is atomic: the first violation rejects the entire payload, so
/// a partially valid config is never applied to memory or disk. Hosts catch
/// this to fall back to the Last-Known-Good cache or compiled-in defaults.
class ConfigValidationException implements Exception {
  /// Creates a validation exception for the JSON node at [path].
  ConfigValidationException(this.path, this.reason);

  /// Dotted JSON path of the offending node (e.g.
  /// `features.new_checkout.rolloutPercentage`).
  final String path;

  /// What was wrong with the node at [path].
  final String reason;

  @override
  String toString() => 'ConfigValidationException at "$path": $reason';
}

Never _fail(String path, String reason) =>
    throw ConfigValidationException(path, reason);

/// Dot-separated numeric version, e.g. `2.1.0`.
final RegExp _versionPattern = RegExp(r'^\d+(\.\d+)*$');

/// Optional audience-segmentation rules for a feature.
class TargetingRules {
  /// Creates targeting rules; both rules are optional.
  const TargetingRules({this.minAppVersion, this.allowedCountries});

  factory TargetingRules._fromJson(Object? json, String path) {
    if (json is! Map<String, Object?>) _fail(path, 'must be an object');

    final minAppVersion = json['minAppVersion'];
    if (minAppVersion != null) {
      if (minAppVersion is! String) {
        _fail('$path.minAppVersion', 'must be a string');
      }
      if (!_versionPattern.hasMatch(minAppVersion)) {
        _fail('$path.minAppVersion',
            'must be a dot-separated numeric version, got "$minAppVersion"');
      }
    }

    final allowedCountries = json['allowedCountries'];
    List<String>? countries;
    if (allowedCountries != null) {
      if (allowedCountries is! List<Object?>) {
        _fail('$path.allowedCountries', 'must be an array');
      }
      countries = <String>[];
      for (final (i, entry) in allowedCountries.indexed) {
        if (entry is! String) {
          _fail('$path.allowedCountries[$i]', 'must be a string');
        }
        countries.add(entry);
      }
    }

    return TargetingRules(
      minAppVersion: minAppVersion as String?,
      allowedCountries: countries,
    );
  }

  /// Minimum app version (inclusive) required to receive the feature.
  final String? minAppVersion;

  /// ISO country codes allowed to receive the feature.
  final List<String>? allowedCountries;

  /// Serializes the rules back to their JSON shape.
  Map<String, Object?> toJson() => {
        if (minAppVersion != null) 'minAppVersion': minAppVersion,
        if (allowedCountries != null) 'allowedCountries': allowedCountries,
      };

  @override
  bool operator ==(Object other) =>
      other is TargetingRules &&
      other.minAppVersion == minAppVersion &&
      _listEquals(other.allowedCountries, allowedCountries);

  @override
  int get hashCode =>
      Object.hash(minAppVersion, Object.hashAll(allowedCountries ?? const []));
}

/// The rollout definition for a single feature flag.
class FeatureConfig {
  /// Creates a feature config.
  const FeatureConfig({
    required this.isKillSwitchActive,
    required this.rolloutPercentage,
    this.targeting,
  });

  factory FeatureConfig._fromJson(Object? json, String path) {
    if (json is! Map<String, Object?>) _fail(path, 'must be an object');

    final killSwitch = json['isKillSwitchActive'];
    if (killSwitch is! bool) {
      _fail(
          '$path.isKillSwitchActive',
          json.containsKey('isKillSwitchActive')
              ? 'must be a boolean'
              : 'is required');
    }

    final rollout = json['rolloutPercentage'];
    if (rollout is! int) {
      _fail(
          '$path.rolloutPercentage',
          json.containsKey('rolloutPercentage')
              ? 'must be an integer'
              : 'is required');
    }
    if (rollout < 0 || rollout > 100) {
      _fail('$path.rolloutPercentage', 'must be 0-100, got $rollout');
    }

    final targeting = json['targeting'];
    return FeatureConfig(
      isKillSwitchActive: killSwitch,
      rolloutPercentage: rollout,
      targeting: targeting == null
          ? null
          : TargetingRules._fromJson(targeting, '$path.targeting'),
    );
  }

  /// Emergency override: when true the feature is disabled for everyone,
  /// regardless of targeting or rollout.
  final bool isKillSwitchActive;

  /// Percentage (0-100) of users receiving the feature, by deterministic
  /// bucket.
  final int rolloutPercentage;

  /// Optional audience rules evaluated after the kill-switch and before the
  /// rollout percentage.
  final TargetingRules? targeting;

  /// Serializes the feature config back to its JSON shape.
  Map<String, Object?> toJson() => {
        'isKillSwitchActive': isKillSwitchActive,
        'rolloutPercentage': rolloutPercentage,
        if (targeting != null) 'targeting': targeting!.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is FeatureConfig &&
      other.isKillSwitchActive == isKillSwitchActive &&
      other.rolloutPercentage == rolloutPercentage &&
      other.targeting == targeting;

  @override
  int get hashCode =>
      Object.hash(isKillSwitchActive, rolloutPercentage, targeting);
}

/// A validated, immutable remote configuration payload.
class RemoteConfig {
  /// Creates a config from already-validated parts.
  RemoteConfig(
      {required this.version, required Map<String, FeatureConfig> features})
      : features = Map.unmodifiable(features);

  /// Validates and parses a decoded JSON object.
  ///
  /// Throws [ConfigValidationException] on the first schema violation;
  /// nothing is partially applied. Unknown keys are ignored for forward
  /// compatibility.
  factory RemoteConfig.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String) {
      _fail('version',
          json.containsKey('version') ? 'must be a string' : 'is required');
    }

    final featuresJson = json['features'];
    if (featuresJson is! Map<String, Object?>) {
      _fail('features',
          json.containsKey('features') ? 'must be an object' : 'is required');
    }

    final features = <String, FeatureConfig>{
      for (final entry in featuresJson.entries)
        entry.key:
            FeatureConfig._fromJson(entry.value, 'features.${entry.key}'),
    };

    return RemoteConfig(version: version, features: features);
  }

  /// Decodes, validates, and parses a raw JSON string (e.g. a network body
  /// or a cached payload).
  ///
  /// Truncated or malformed JSON surfaces as [ConfigValidationException],
  /// so hosts have a single failure type to catch before falling back to
  /// the Last-Known-Good config.
  factory RemoteConfig.parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      _fail(r'$', 'payload is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      _fail(r'$', 'root must be a JSON object');
    }
    return RemoteConfig.fromJson(decoded);
  }

  /// Config payload version identifier, for diagnostics and cache metadata.
  final String version;

  /// Feature definitions keyed by feature key. Unmodifiable.
  final Map<String, FeatureConfig> features;

  /// Serializes the config back to its JSON shape (used by LKG caches).
  Map<String, Object?> toJson() => {
        'version': version,
        'features': {
          for (final entry in features.entries) entry.key: entry.value.toJson(),
        },
      };

  @override
  bool operator ==(Object other) =>
      other is RemoteConfig &&
      other.version == version &&
      _mapEquals(other.features, features);

  @override
  int get hashCode => Object.hash(
      version, Object.hashAllUnordered(features.keys), features.length);
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
