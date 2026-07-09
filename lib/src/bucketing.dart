import 'dart:convert';

import 'hashing/murmur3.dart';

/// Computes the deterministic rollout bucket (0-99) for a user and feature.
///
/// The bucket is `murmur3_x86_32(utf8("userId:featureKey")) % 100`. Because
/// the hash is stable, a user's bucket for a given feature never changes
/// across sessions, devices, or app restarts. Because the feature key is part
/// of the payload, the same user lands in independent buckets for different
/// features, preventing sticky cohorts where one group of users receives
/// every early rollout at once.
///
/// The colon separator makes the userId/featureKey boundary unambiguous:
/// without it, `("user1", "2checkout")` and `("user12", "checkout")` would
/// hash identically.
///
/// This mapping is permanent. Changing the algorithm, seed, or payload format
/// reassigns every user's bucket and must never ship; pinned regression
/// vectors in the test suite guard against accidental changes.
int getRolloutBucket(String userId, String featureKey) {
  final payload = utf8.encode('$userId:$featureKey');
  return murmur3X86_32(payload) % 100;
}
