import 'package:feature_flag_kit/feature_flag_kit.dart';
import 'package:test/test.dart';

void main() {
  group('getRolloutBucket', () {
    test('is stable across repeated calls', () {
      final first = getRolloutBucket('user123', 'new_checkout');
      for (var i = 0; i < 1000; i++) {
        expect(getRolloutBucket('user123', 'new_checkout'), first);
      }
    });

    test('is always in range 0-99', () {
      for (var i = 0; i < 1000; i++) {
        final bucket = getRolloutBucket('user$i', 'new_checkout');
        expect(bucket, inInclusiveRange(0, 99));
      }
    });

    test('same user gets independent buckets per feature (no sticky cohorts)',
        () {
      // Across many features, one user's buckets must not all collide.
      final buckets = <int>{
        for (var i = 0; i < 50; i++) getRolloutBucket('user123', 'feature_$i'),
      };
      expect(buckets.length, greaterThan(10));
    });

    test('separator prevents concatenation ambiguity', () {
      // Without the colon separator these two would hash identically.
      expect(
        getRolloutBucket('user1', '2checkout') ==
                getRolloutBucket('user12', 'checkout') &&
            getRolloutBucket('user1', '2promo') ==
                getRolloutBucket('user12', 'promo'),
        isFalse,
        reason: 'userId/featureKey boundary must be unambiguous',
      );
    });

    test('distribution across 10k users is roughly uniform', () {
      final counts = List.filled(100, 0);
      for (var i = 0; i < 10000; i++) {
        counts[getRolloutBucket('user_$i', 'new_checkout')]++;
      }
      // Expected 100 per bucket; allow generous bounds to avoid flakiness
      // while still catching gross skew.
      for (var bucket = 0; bucket < 100; bucket++) {
        expect(counts[bucket], inInclusiveRange(50, 200),
            reason: 'bucket $bucket is badly skewed');
      }
    });

    test('rollout population scales linearly with percentage', () {
      // ~20% of 10k users should fall below bucket 20.
      var inRollout = 0;
      for (var i = 0; i < 10000; i++) {
        if (getRolloutBucket('user_$i', 'new_checkout') < 20) inRollout++;
      }
      expect(inRollout, inInclusiveRange(1700, 2300));
    });
  });

  group('getRolloutBucket pinned regression vectors', () {
    // PERMANENCE GUARD: these exact values must never change. If this test
    // fails, the hash algorithm, seed, or payload format has changed, which
    // silently reassigns every user's bucket for every feature. Such a
    // change must not ship. Values are computed from the vendored
    // murmur3X86_32("userId:featureKey", seed 0) % 100.
    test('known user/feature pairs map to pinned buckets', () {
      expect(getRolloutBucket('user_a', 'new_checkout'), 10);
      expect(getRolloutBucket('user_b', 'new_checkout'), 82);
      expect(getRolloutBucket('user_a', 'promo_banner'), 1);
      expect(getRolloutBucket('anonymous', 'new_checkout'), 2);
      expect(
        getRolloutBucket('550e8400-e29b-41d4-a716-446655440000', 'dark_mode'),
        66,
      );
    });
  });
}
