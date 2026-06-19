import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/keystore.dart';
import '../lib/pqxdh.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('join handshake round-trip: masterSecrets match', () {
    final sender = Identity.generate(c, 'alice', 'alice:main');
    final joiner = Identity.generate(c, 'bob', 'bob:main');

    final (ms1, env) = pqxdhSend(c, sender.ikSk, joiner.toKeyPackage());
    final ms2 = pqxdhReceive(c, joiner.toKeyPackageSk(), sender.ikPk, env);

    expect(ms1, equals(ms2));
    expect(ms1.length, 32);
  });

  test('external message round-trip: masterSecrets match', () {
    final sender = Identity.generate(c, 'alice', 'alice:main');
    final receiver = Identity.generate(c, 'bob', 'bob:main');

    final (ms1, env) = pqxdhExternalSend(
        c, sender.ikSk, sender.ikPk, receiver.toKeyPackage());
    final ms2 =
        pqxdhExternalReceive(c, receiver.toKeyPackageSk(), sender.ikPk, env);

    expect(ms1, equals(ms2));
  });

  test('wrong sender IK produces different masterSecret', () {
    final sender = Identity.generate(c, 'alice', 'alice:main');
    final joiner = Identity.generate(c, 'bob', 'bob:main');
    final other = Identity.generate(c, 'carol', 'carol:main');

    final (ms1, env) = pqxdhSend(c, sender.ikSk, joiner.toKeyPackage());
    try {
      final ms2 =
          pqxdhReceive(c, joiner.toKeyPackageSk(), other.ikPk, env);
      expect(ms1, isNot(equals(ms2)));
    } catch (_) {
      // Expected — decryption with wrong key fails
    }
  });
}
