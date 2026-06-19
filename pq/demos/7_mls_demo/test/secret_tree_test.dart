import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/secret_tree.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('in-order derivation produces 32B key + 12B nonce', () {
    final enc = Uint8List(32)..fillRange(0, 32, 0x01);
    final st = SecretTree(c.hmac, enc, 4);
    final k0 = st.getRatchet(0).deriveMessageKey(0);
    expect(k0.key.length, 32);
    expect(k0.nonce.length, 12);
  });

  test('consecutive keys are different', () {
    final enc = Uint8List(32)..fillRange(0, 32, 0x02);
    final st = SecretTree(c.hmac, enc, 4);
    final r = st.getRatchet(0);
    final k0 = r.deriveMessageKey(0);
    final k1 = r.deriveMessageKey(1);
    expect(k0.key, isNot(equals(k1.key)));
  });

  test('out-of-order delivery skips correctly', () {
    final enc = Uint8List(32)..fillRange(0, 32, 0x03);
    final st = SecretTree(c.hmac, enc, 4);
    final r = st.getRatchet(0);
    final k2 = r.deriveMessageKey(2); // skips 0 and 1
    expect(k2.key.length, 32);
    // Can now retrieve skipped keys
    final k0 = r.deriveMessageKey(0);
    expect(k0.key.length, 32);
  });

  test('re-using consumed key throws', () {
    final enc = Uint8List(32)..fillRange(0, 32, 0x04);
    final st = SecretTree(c.hmac, enc, 2);
    final r = st.getRatchet(0);
    r.deriveMessageKey(0);
    expect(() => r.deriveMessageKey(0), throwsStateError);
  });

  test('different leaves produce different keys', () {
    final enc = Uint8List(32)..fillRange(0, 32, 0x05);
    final st = SecretTree(c.hmac, enc, 4);
    final k0 = st.getRatchet(0).deriveMessageKey(0);
    final k1 = st.getRatchet(1).deriveMessageKey(0);
    expect(k0.key, isNot(equals(k1.key)));
  });
}
