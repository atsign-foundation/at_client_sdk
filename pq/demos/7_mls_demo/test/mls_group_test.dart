import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pq_demo_6/openssl.dart';
import '../lib/keystore.dart';
import '../lib/mls_group.dart';

void main() {
  late Crypto c;
  setUp(() => c = Crypto.load());

  test('create: solo group at epoch 0', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final g = MlsGroup.create(c, alice);
    expect(g.epoch, 0);
    expect(g.memberDevices, contains('alice:main'));
  });

  test('encrypt/decrypt round-trip in same instance', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final g = MlsGroup.create(c, alice);
    final ct = g.encrypt('hello MLS');
    final r = g.decrypt(ct);
    expect(r.plaintext, 'hello MLS');
    expect(r.senderDevice, 'alice:main');
  });

  test('multiple messages use different generations', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final g = MlsGroup.create(c, alice);
    final ct0 = g.encrypt('msg0');
    final ct1 = g.encrypt('msg1');
    expect(ct0.generation, 0);
    expect(ct1.generation, 1);
    expect(ct0.ct, isNot(equals(ct1.ct)));
  });

  test('addMember + applyWelcome: two-party group, cross-encrypt', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final bob = Identity.generate(c, 'bob', 'bob:main');

    final aliceGroup = MlsGroup.create(c, alice);
    final result = aliceGroup.addMember(bob.toKeyPackage());

    final bobGroup = MlsGroup.applyWelcome(c, bob, result.welcome);
    expect(bobGroup.epoch, 1);
    expect(bobGroup.memberDevices, containsAll(['alice:main', 'bob:main']));

    // Alice → Bob
    final ct1 = aliceGroup.encrypt('hello bob');
    final dec1 = bobGroup.decrypt(ct1);
    expect(dec1.plaintext, 'hello bob');
    expect(dec1.senderDevice, 'alice:main');

    // Bob → Alice
    final ct2 = bobGroup.encrypt('hello alice');
    final dec2 = aliceGroup.decrypt(ct2);
    expect(dec2.plaintext, 'hello alice');
    expect(dec2.senderDevice, 'bob:main');
  });

  test('three-party: non-committer applyCommit reaches same epoch secrets', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final bob = Identity.generate(c, 'bob', 'bob:main');
    final carol = Identity.generate(c, 'carol', 'carol:main');

    // Alice creates group and adds Bob.
    final aliceGroup = MlsGroup.create(c, alice);
    final r1 = aliceGroup.addMember(bob.toKeyPackage());
    final bobGroup = MlsGroup.applyWelcome(c, bob, r1.welcome);

    // Alice adds Carol — Bob is a non-committer and must applyCommit.
    final r2 = aliceGroup.addMember(carol.toKeyPackage());
    bobGroup.applyCommit(r2.commit);
    final carolGroup = MlsGroup.applyWelcome(c, carol, r2.welcome);

    expect(aliceGroup.epoch, 2);
    expect(bobGroup.epoch, 2);
    expect(carolGroup.epoch, 2);

    // All three can cross-decrypt each other's messages.
    final ctA = aliceGroup.encrypt('from alice');
    expect(bobGroup.decrypt(ctA).plaintext, 'from alice');
    expect(carolGroup.decrypt(ctA).plaintext, 'from alice');

    final ctB = bobGroup.encrypt('from bob');
    expect(aliceGroup.decrypt(ctB).plaintext, 'from bob');
    expect(carolGroup.decrypt(ctB).plaintext, 'from bob');

    final ctC = carolGroup.encrypt('from carol');
    expect(aliceGroup.decrypt(ctC).plaintext, 'from carol');
    expect(bobGroup.decrypt(ctC).plaintext, 'from carol');
  });

  test('removed member cannot decrypt post-removal messages', () {
    final alice = Identity.generate(c, 'alice', 'alice:main');
    final bob = Identity.generate(c, 'bob', 'bob:main');

    final aliceGroup = MlsGroup.create(c, alice);
    final addResult = aliceGroup.addMember(bob.toKeyPackage());
    final bobGroup = MlsGroup.applyWelcome(c, bob, addResult.welcome);

    // Alice removes Bob and sends a post-removal message
    aliceGroup.removeMember('bob:main');
    final ct = aliceGroup.encrypt('secret after removal');

    // Bob's stale group cannot decrypt (different epoch + no epoch secret)
    expect(() => bobGroup.decrypt(ct), throwsA(anything));
  });
}
