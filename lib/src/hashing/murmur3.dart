/// Vendored MurmurHash3, x86 32-bit variant.
///
/// Ported from Austin Appleby's public-domain reference implementation
/// (MurmurHash3_x86_32) and verified against published test vectors. This is
/// the same algorithm used for bucketing by LaunchDarkly, Unleash,
/// GrowthBook, and Flagsmith.
///
/// Vendored rather than depended upon so the package keeps zero runtime
/// dependencies, and pinned by test vectors because bucket assignments
/// derived from it are permanent: any change to the algorithm silently
/// reassigns every user's rollout bucket.
library;

const int _c1 = 0xcc9e2d51;
const int _c2 = 0x1b873593;

/// Computes the MurmurHash3 x86 32-bit hash of [bytes] with the given [seed].
///
/// Returns an unsigned 32-bit integer (0 to 0xFFFFFFFF). All arithmetic is
/// performed in 32-bit space using 16-bit limb multiplication, so results
/// are identical on the Dart VM and on the web (where integers are IEEE
/// doubles with 53 bits of precision).
int murmur3X86_32(List<int> bytes, [int seed = 0]) {
  final length = bytes.length;
  final nBlocks = length ~/ 4;
  var h1 = seed & 0xFFFFFFFF;

  // Body: process 4-byte little-endian blocks.
  for (var i = 0; i < nBlocks; i++) {
    final base = i * 4;
    var k1 = (bytes[base] & 0xFF) |
        ((bytes[base + 1] & 0xFF) << 8) |
        ((bytes[base + 2] & 0xFF) << 16) |
        ((bytes[base + 3] & 0xFF) << 24);
    k1 = _mul32(k1, _c1);
    k1 = _rotl32(k1, 15);
    k1 = _mul32(k1, _c2);
    h1 ^= k1;
    h1 = _rotl32(h1, 13);
    h1 = (_mul32(h1, 5) + 0xe6546b64) & 0xFFFFFFFF;
  }

  // Tail: remaining 1-3 bytes.
  final tail = nBlocks * 4;
  final remainder = length & 3;
  var k1 = 0;
  if (remainder == 3) k1 ^= (bytes[tail + 2] & 0xFF) << 16;
  if (remainder >= 2) k1 ^= (bytes[tail + 1] & 0xFF) << 8;
  if (remainder >= 1) {
    k1 ^= bytes[tail] & 0xFF;
    k1 = _mul32(k1, _c1);
    k1 = _rotl32(k1, 15);
    k1 = _mul32(k1, _c2);
    h1 ^= k1;
  }

  // Finalization: force avalanche of the last few bits.
  h1 ^= length;
  h1 ^= h1 >>> 16;
  h1 = _mul32(h1, 0x85ebca6b);
  h1 ^= h1 >>> 13;
  h1 = _mul32(h1, 0xc2b2ae35);
  h1 ^= h1 >>> 16;
  return h1;
}

/// 32-bit multiplication via 16-bit limbs; intermediate products stay below
/// 2^48, within the 53-bit safe-integer range required on the web.
int _mul32(int a, int b) {
  final low = (a & 0xFFFF) * b;
  final high = (((a >>> 16) & 0xFFFF) * b & 0xFFFF) << 16;
  return (low + high) & 0xFFFFFFFF;
}

/// Rotates a 32-bit value left by [r] bits.
int _rotl32(int x, int r) => ((x << r) | (x >>> (32 - r))) & 0xFFFFFFFF;
