import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/epoch.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('different commitSecrets yield different encryptionSecrets', () {
    final init = Uint8List(32)..fillRange(0, 32, 0x01);
    final ctx = Uint8List.fromList('test-group'.codeUnits);
    final cs1 = Uint8List(32)..fillRange(0, 32, 0x10);
    final cs2 = Uint8List(32)..fillRange(0, 32, 0x20);
    final e1 = deriveEpochSecrets(c.hmac, init, cs1, ctx);
    final e2 = deriveEpochSecrets(c.hmac, init, cs2, ctx);
    expect(e1.encryptionSecret, isNot(equals(e2.encryptionSecret)));
  });

  test('initSecret chain is one-way', () {
    final init0 = Uint8List(32)..fillRange(0, 32, 0x01);
    final ctx = Uint8List.fromList('grp'.codeUnits);
    final cs = Uint8List(32)..fillRange(0, 32, 0x05);
    final e1 = deriveEpochSecrets(c.hmac, init0, cs, ctx);
    final e2 = deriveEpochSecrets(c.hmac, e1.initSecret, cs, ctx);
    expect(e1.initSecret, isNot(equals(e2.initSecret)));
    expect(e1.encryptionSecret, isNot(equals(e2.encryptionSecret)));
  });

  test('deriveWelcomeKey produces 32B key + 12B nonce', () {
    final js = Uint8List(32)..fillRange(0, 32, 0x42);
    final (key, nonce) = deriveWelcomeKey(c.hmac, js);
    expect(key.length, 32);
    expect(nonce.length, 12);
  });
}
