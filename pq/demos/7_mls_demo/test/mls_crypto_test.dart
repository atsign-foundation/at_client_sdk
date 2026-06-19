import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/mls_crypto.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('expandWithLabel produces requested length', () {
    final secret = Uint8List(32)..fillRange(0, 32, 0x01);
    expect(expandWithLabel(c.hmac, secret, 'test', Uint8List(0), 32).length, 32);
    expect(expandWithLabel(c.hmac, secret, 'test', Uint8List(0), 12).length, 12);
  });

  test('expandWithLabel is deterministic', () {
    final secret = Uint8List(32)..fillRange(0, 32, 0x42);
    final a = expandWithLabel(c.hmac, secret, 'label', Uint8List(0), 32);
    final b = expandWithLabel(c.hmac, secret, 'label', Uint8List(0), 32);
    expect(a, equals(b));
  });

  test('expandWithLabel different labels produce different outputs', () {
    final secret = Uint8List(32)..fillRange(0, 32, 0x01);
    final a = expandWithLabel(c.hmac, secret, 'label1', Uint8List(0), 32);
    final b = expandWithLabel(c.hmac, secret, 'label2', Uint8List(0), 32);
    expect(a, isNot(equals(b)));
  });

  test('deriveSecret returns 32 bytes', () {
    final secret = Uint8List(32)..fillRange(0, 32, 0xab);
    expect(deriveSecret(c.hmac, secret, 'test').length, 32);
  });

  test('hkdfExtract is salt-sensitive', () {
    final ikm = Uint8List(32)..fillRange(0, 32, 0x01);
    final a = hkdfExtract(c.hmac, Uint8List(32), ikm);
    final b = hkdfExtract(c.hmac, Uint8List(32)..fillRange(0, 32, 0x02), ikm);
    expect(a, isNot(equals(b)));
  });
}
