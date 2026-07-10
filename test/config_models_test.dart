import 'package:feature_flag_kit/feature_flag_kit.dart';
import 'package:test/test.dart';

/// A structurally valid config exercising every schema field.
Map<String, Object?> validConfigJson() => {
      'version': 'v1.0',
      'features': {
        'new_checkout': {
          'isKillSwitchActive': false,
          'rolloutPercentage': 50,
          'targeting': {
            'minAppVersion': '2.1.0',
            'allowedCountries': ['US', 'CA'],
          },
        },
        'promo_banner': {
          'isKillSwitchActive': true,
          'rolloutPercentage': 100,
        },
      },
    };

void main() {
  group('RemoteConfig.fromJson accepts valid configs', () {
    test('parses a full config with targeting', () {
      final config = RemoteConfig.fromJson(validConfigJson());

      expect(config.version, 'v1.0');
      expect(config.features, hasLength(2));

      final checkout = config.features['new_checkout']!;
      expect(checkout.isKillSwitchActive, isFalse);
      expect(checkout.rolloutPercentage, 50);
      expect(checkout.targeting!.minAppVersion, '2.1.0');
      expect(checkout.targeting!.allowedCountries, ['US', 'CA']);

      final promo = config.features['promo_banner']!;
      expect(promo.isKillSwitchActive, isTrue);
      expect(promo.rolloutPercentage, 100);
      expect(promo.targeting, isNull);
    });

    test('parses an empty features map', () {
      final config = RemoteConfig.fromJson(
          {'version': 'v2', 'features': <String, Object?>{}});
      expect(config.features, isEmpty);
    });

    test('ignores unknown keys for forward compatibility', () {
      final json = validConfigJson();
      json['futureTopLevelKey'] = 123;
      (json['features']! as Map<String, Object?>)['new_checkout'] = {
        'isKillSwitchActive': false,
        'rolloutPercentage': 50,
        'futureFeatureKey': 'x',
      };
      expect(RemoteConfig.fromJson(json), isA<RemoteConfig>());
    });

    test('boundary rollout percentages 0 and 100 are valid', () {
      for (final pct in [0, 100]) {
        final config = RemoteConfig.fromJson({
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': false, 'rolloutPercentage': pct},
          },
        });
        expect(config.features['f']!.rolloutPercentage, pct);
      }
    });
  });

  group('RemoteConfig.fromJson rejects invalid configs', () {
    // Each case: (description, mutated json, expected path fragment in error).
    final cases = <(String, Map<String, Object?>, String)>[
      (
        'missing version',
        {'features': <String, Object?>{}},
        'version',
      ),
      (
        'non-string version',
        {'version': 2, 'features': <String, Object?>{}},
        'version',
      ),
      (
        'missing features',
        {'version': 'v1'},
        'features',
      ),
      (
        'features is a list, not a map',
        {'version': 'v1', 'features': <Object?>[]},
        'features',
      ),
      (
        'feature entry is not a map',
        {
          'version': 'v1',
          'features': {'f': 42},
        },
        'features.f',
      ),
      (
        'missing isKillSwitchActive',
        {
          'version': 'v1',
          'features': {
            'f': {'rolloutPercentage': 50},
          },
        },
        'features.f.isKillSwitchActive',
      ),
      (
        'non-bool isKillSwitchActive',
        {
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': 'true', 'rolloutPercentage': 50},
          },
        },
        'features.f.isKillSwitchActive',
      ),
      (
        'missing rolloutPercentage',
        {
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': false},
          },
        },
        'features.f.rolloutPercentage',
      ),
      (
        'non-integer rolloutPercentage',
        {
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': false, 'rolloutPercentage': 50.5},
          },
        },
        'features.f.rolloutPercentage',
      ),
      (
        'rolloutPercentage below 0',
        {
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': false, 'rolloutPercentage': -1},
          },
        },
        'features.f.rolloutPercentage',
      ),
      (
        'rolloutPercentage above 100',
        {
          'version': 'v1',
          'features': {
            'f': {'isKillSwitchActive': false, 'rolloutPercentage': 101},
          },
        },
        'features.f.rolloutPercentage',
      ),
      (
        'targeting is not a map',
        {
          'version': 'v1',
          'features': {
            'f': {
              'isKillSwitchActive': false,
              'rolloutPercentage': 50,
              'targeting': 'US',
            },
          },
        },
        'features.f.targeting',
      ),
      (
        'non-string minAppVersion',
        {
          'version': 'v1',
          'features': {
            'f': {
              'isKillSwitchActive': false,
              'rolloutPercentage': 50,
              'targeting': {'minAppVersion': 2.1},
            },
          },
        },
        'features.f.targeting.minAppVersion',
      ),
      (
        'malformed minAppVersion',
        {
          'version': 'v1',
          'features': {
            'f': {
              'isKillSwitchActive': false,
              'rolloutPercentage': 50,
              'targeting': {'minAppVersion': 'two.point.one'},
            },
          },
        },
        'features.f.targeting.minAppVersion',
      ),
      (
        'allowedCountries is not a list',
        {
          'version': 'v1',
          'features': {
            'f': {
              'isKillSwitchActive': false,
              'rolloutPercentage': 50,
              'targeting': {'allowedCountries': 'US'},
            },
          },
        },
        'features.f.targeting.allowedCountries',
      ),
      (
        'allowedCountries contains a non-string',
        {
          'version': 'v1',
          'features': {
            'f': {
              'isKillSwitchActive': false,
              'rolloutPercentage': 50,
              'targeting': {
                'allowedCountries': ['US', 1],
              },
            },
          },
        },
        'features.f.targeting.allowedCountries',
      ),
    ];

    for (final (description, json, pathFragment) in cases) {
      test(description, () {
        expect(
          () => RemoteConfig.fromJson(json),
          throwsA(
            isA<ConfigValidationException>().having(
              (e) => e.toString(),
              'message',
              contains(pathFragment),
            ),
          ),
        );
      });
    }

    test('one invalid feature rejects the whole config (atomicity)', () {
      final json = validConfigJson();
      (json['features']! as Map<String, Object?>)['broken'] = {
        'isKillSwitchActive': false,
        'rolloutPercentage': 'half',
      };
      expect(
        () => RemoteConfig.fromJson(json),
        throwsA(isA<ConfigValidationException>()),
      );
    });
  });

  group('RemoteConfig.parse (string payloads)', () {
    test('parses a valid JSON string', () {
      const raw = '{"version":"v1","features":{"f":{"isKillSwitchActive":false,'
          '"rolloutPercentage":25}}}';
      expect(RemoteConfig.parse(raw).features['f']!.rolloutPercentage, 25);
    });

    test('rejects truncated JSON as ConfigValidationException', () {
      const truncated = '{"version":"v1","features":{"f":{"isKill';
      expect(
        () => RemoteConfig.parse(truncated),
        throwsA(isA<ConfigValidationException>()),
      );
    });

    test('rejects a JSON array root', () {
      expect(
        () => RemoteConfig.parse('[1,2,3]'),
        throwsA(isA<ConfigValidationException>()),
      );
    });
  });

  group('round-trip serialization', () {
    test('toJson -> fromJson preserves the config', () {
      final original = RemoteConfig.fromJson(validConfigJson());
      final restored = RemoteConfig.fromJson(original.toJson());
      expect(restored, original);
    });
  });

  group('UserContext', () {
    test('holds identity and targeting attributes', () {
      final context =
          UserContext(userId: 'user_a', country: 'US', appVersion: '2.1.0');
      expect(context.userId, 'user_a');
      expect(context.country, 'US');
      expect(context.appVersion, '2.1.0');
    });

    test('rejects an empty userId', () {
      expect(() => UserContext(userId: ''), throwsArgumentError);
    });

    test('value equality', () {
      expect(
        UserContext(userId: 'u', country: 'US'),
        UserContext(userId: 'u', country: 'US'),
      );
      expect(
        UserContext(userId: 'u', country: 'US'),
        isNot(UserContext(userId: 'u', country: 'CA')),
      );
    });
  });

  group('EvaluationResult', () {
    test('carries decision, reason, and debug message', () {
      const result = EvaluationResult(
        isEnabled: true,
        reason: EvaluationReason.rolloutHit,
        debugMessage: 'bucket 10 < 50%',
      );
      expect(result.isEnabled, isTrue);
      expect(result.reason, EvaluationReason.rolloutHit);
      expect(result.debugMessage, contains('bucket 10'));
    });
  });
}
