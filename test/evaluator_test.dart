import 'package:feature_flag_kit/feature_flag_kit.dart';
import 'package:test/test.dart';

// Pinned buckets (see bucketing_test.dart permanence guard):
//   user_a : new_checkout -> 10
//   user_b : new_checkout -> 82
RemoteConfig configWith(FeatureConfig feature, {String key = 'new_checkout'}) =>
    RemoteConfig(version: 'v1', features: {key: feature});

UserContext userA({String? country, String? appVersion}) =>
    UserContext(userId: 'user_a', country: country, appVersion: appVersion);

void main() {
  group('hierarchy step 0: fallback', () {
    test('missing feature returns disabled with fallback reason', () {
      final result = evaluateFlag(
        featureKey: 'does_not_exist',
        user: userA(),
        config: RemoteConfig(version: 'v1', features: const {}),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.fallback);
      expect(result.debugMessage, contains('does_not_exist'));
    });
  });

  group('hierarchy step 1: kill-switch', () {
    test('kill-switch disables even at 100% rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(
          const FeatureConfig(isKillSwitchActive: true, rolloutPercentage: 100),
        ),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.killSwitch);
    });

    test('kill-switch outranks targeting (reported reason is killSwitch)', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'IN'),
        config: configWith(
          const FeatureConfig(
            isKillSwitchActive: true,
            rolloutPercentage: 100,
            targeting: TargetingRules(allowedCountries: ['US']),
          ),
        ),
      );
      expect(result.reason, EvaluationReason.killSwitch);
    });
  });

  group('hierarchy step 2: targeting', () {
    FeatureConfig targeted(TargetingRules rules) => FeatureConfig(
          isKillSwitchActive: false,
          rolloutPercentage: 100,
          targeting: rules,
        );

    test('country in allowedCountries passes through to rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'US'),
        config: configWith(
            targeted(const TargetingRules(allowedCountries: ['US', 'CA']))),
      );
      expect(result.isEnabled, isTrue);
      expect(result.reason, EvaluationReason.rolloutHit);
    });

    test('country not in allowedCountries misses', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'IN'),
        config: configWith(
            targeted(const TargetingRules(allowedCountries: ['US', 'CA']))),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.targetingMiss);
      expect(result.debugMessage, contains('IN'));
    });

    test('country rule with unknown user country misses (safe default)', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(
            targeted(const TargetingRules(allowedCountries: ['US']))),
      );
      expect(result.reason, EvaluationReason.targetingMiss);
    });

    test('country match is case-insensitive', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'us'),
        config: configWith(
            targeted(const TargetingRules(allowedCountries: ['US']))),
      );
      expect(result.isEnabled, isTrue);
    });

    group('minAppVersion comparison is numeric per component', () {
      final cases = <(String userVersion, String minVersion, bool passes)>[
        ('2.1.0', '2.1.0', true), // equal
        ('2.2.0', '2.1.0', true), // greater minor
        ('3.0.0', '2.9.9', true), // greater major
        ('2.10.0', '2.9.0', true), // numeric, not lexicographic
        ('2.0.9', '2.1.0', false), // lesser
        ('1.9.9', '2.0.0', false), // lesser major
        ('2.1', '2.1.0', true), // missing components count as zero
        ('2.1.0.1', '2.1.0', true), // more components than the rule
      ];
      for (final (userVersion, minVersion, passes) in cases) {
        test('$userVersion vs min $minVersion -> ${passes ? 'pass' : 'miss'}',
            () {
          final result = evaluateFlag(
            featureKey: 'new_checkout',
            user: userA(appVersion: userVersion),
            config:
                configWith(targeted(TargetingRules(minAppVersion: minVersion))),
          );
          expect(
            result.reason,
            passes
                ? EvaluationReason.rolloutHit
                : EvaluationReason.targetingMiss,
          );
        });
      }
    });

    test('version rule with unknown user appVersion misses (safe default)', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config:
            configWith(targeted(const TargetingRules(minAppVersion: '1.0'))),
      );
      expect(result.reason, EvaluationReason.targetingMiss);
    });

    test('both rules must pass (AND semantics)', () {
      final rules = const TargetingRules(
        minAppVersion: '2.0.0',
        allowedCountries: ['US'],
      );
      final passing = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'US', appVersion: '2.5.0'),
        config: configWith(targeted(rules)),
      );
      expect(passing.isEnabled, isTrue);

      final wrongCountry = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'IN', appVersion: '2.5.0'),
        config: configWith(targeted(rules)),
      );
      expect(wrongCountry.reason, EvaluationReason.targetingMiss);

      final oldVersion = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(country: 'US', appVersion: '1.0.0'),
        config: configWith(targeted(rules)),
      );
      expect(oldVersion.reason, EvaluationReason.targetingMiss);
    });
  });

  group('hierarchy step 3: percentage rollout', () {
    FeatureConfig rollout(int pct) =>
        FeatureConfig(isKillSwitchActive: false, rolloutPercentage: pct);

    test('100% short-circuits to enabled', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(rollout(100)),
      );
      expect(result.isEnabled, isTrue);
      expect(result.reason, EvaluationReason.rolloutHit);
    });

    test('0% short-circuits to disabled', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(rollout(0)),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.rolloutMiss);
    });

    test('user_a (bucket 10) is inside a 50% rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(rollout(50)),
      );
      expect(result.isEnabled, isTrue);
      expect(result.reason, EvaluationReason.rolloutHit);
      expect(result.debugMessage, contains('bucket 10'));
      expect(result.debugMessage, contains('50%'));
    });

    test('user_b (bucket 82) is outside a 50% rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: UserContext(userId: 'user_b'),
        config: configWith(rollout(50)),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.rolloutMiss);
      expect(result.debugMessage, contains('bucket 82'));
    });

    test('boundary is strict: bucket 10 is outside a 10% rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(rollout(10)),
      );
      expect(result.isEnabled, isFalse);
      expect(result.reason, EvaluationReason.rolloutMiss);
    });

    test('boundary: bucket 10 is inside an 11% rollout', () {
      final result = evaluateFlag(
        featureKey: 'new_checkout',
        user: userA(),
        config: configWith(rollout(11)),
      );
      expect(result.isEnabled, isTrue);
    });
  });
}
