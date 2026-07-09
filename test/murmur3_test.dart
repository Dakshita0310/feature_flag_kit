import 'dart:convert';

import 'package:feature_flag_kit/src/hashing/murmur3.dart';
import 'package:test/test.dart';

/// Published MurmurHash3 x86 32-bit reference vectors.
///
/// These pin the vendored implementation to the canonical algorithm
/// (Austin Appleby's MurmurHash3_x86_32). If any of these fail, the
/// implementation does not match the industry-standard hash and MUST NOT
/// ship: every consumer's bucket assignments would differ from spec.
void main() {
  group('murmur3X86_32 reference vectors', () {
    test('empty input, seed 0', () {
      expect(murmur3X86_32([], 0), 0x00000000);
    });

    test('empty input, seed 1', () {
      expect(murmur3X86_32([], 1), 0x514E28B7);
    });

    test('empty input, seed 0xFFFFFFFF', () {
      expect(murmur3X86_32([], 0xFFFFFFFF), 0x81F16F39);
    });

    test('four 0xFF bytes, seed 0', () {
      expect(murmur3X86_32([0xFF, 0xFF, 0xFF, 0xFF], 0), 0x76293B50);
    });

    test('one-byte tail 0x21, seed 0', () {
      expect(murmur3X86_32([0x21], 0), 0x72661CF4);
    });

    test('two-byte tail 0x21 0x43, seed 0', () {
      expect(murmur3X86_32([0x21, 0x43], 0), 0xA0F7B07A);
    });

    test('three-byte tail 0x21 0x43 0x65, seed 0', () {
      expect(murmur3X86_32([0x21, 0x43, 0x65], 0), 0x7E4A8634);
    });

    test('full block 0x21 0x43 0x65 0x87, seed 0', () {
      expect(murmur3X86_32([0x21, 0x43, 0x65, 0x87], 0), 0xF55B516B);
    });

    test('full block 0x21 0x43 0x65 0x87, seed 0x5082EDEE', () {
      expect(murmur3X86_32([0x21, 0x43, 0x65, 0x87], 0x5082EDEE), 0x2362F9DE);
    });

    test('four zero bytes, seed 0', () {
      expect(murmur3X86_32([0, 0, 0, 0], 0), 0x2362F9DE);
    });
  });

  group('murmur3X86_32 properties', () {
    test('output is always an unsigned 32-bit integer', () {
      for (final input in ['a', 'ab', 'abc', 'abcd', 'abcde', 'user42:flag']) {
        final hash = murmur3X86_32(utf8.encode(input), 0);
        expect(hash, inInclusiveRange(0, 0xFFFFFFFF));
      }
    });

    test('is deterministic across repeated calls', () {
      final bytes = utf8.encode('user123:new_checkout');
      final first = murmur3X86_32(bytes, 0);
      for (var i = 0; i < 100; i++) {
        expect(murmur3X86_32(bytes, 0), first);
      }
    });
  });
}
