// The substrate and the signing root are @experimental; driving them is the
// point of this file.
// ignore_for_file: experimental_member_use

import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The signing-root pull between two real APKAM enrollments.
///
/// This is the route an enrollment takes when it was offline during the wave
/// that conveyed the root: the root is atSign-level and carries no namespace,
/// so it never rides the `enroll:listns` fan-out, and it is immutable and
/// never rotates, so nothing can mint a replacement.
///
/// It needs two genuine enrollments and nothing less. The pull authenticates
/// on **both** sides — the requester to enumerate holders, the responder to
/// authorize the requester before answering — and both go through
/// `enroll:listns`, which the atServer answers only for an APKAM-authenticated
/// connection. A client using the atSign's own keys is refused at either end,
/// which is why the earlier single-client attempt could not reach this and why
/// `enrolAndAuthenticate` exists.
void main() {
  late AtClient approver;
  late String atSign;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();
  });

  Future<EnrolledClient> enrol(String device) => enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: device,
      );

  // SKIPPED — the fixture is not finished, and the two open points are named
  // rather than guessed at:
  //
  // 1. The enrolled client is not APKAM-authenticated because it is not a new
  //    client at all. AtClientImpl caches instances keyed by atSign ALONE, so
  //    every call returns the same object as the approver's client —
  //    identical(enrolled.client, approver) is true, and two enrollments of
  //    one atSign are identical to each other. enrollmentId therefore never
  //    reaches the AtLookUp. The session was fine throughout: it carries the
  //    right enrollmentId and an already-authenticated AtLookUp, and
  //    fromAuthSession(reuse: true) still changes nothing, because none of
  //    those arguments are applied to a cached instance. Fixing it is a
  //    decision about AtClientImpl — a cache scoped by (atSign, enrollmentId),
  //    or driving the second enrollment through AtLookUp alone, or a second
  //    process — not a fixture detail.
  //
  // 2. Each party must bind its key package to its enrollment's, via
  //    `bindKeyPackageToAtKeys`. `register()` mints a fresh X-Wing keypair per
  //    process — observed: a party's kpid came back 490de1fc0a10864e where its
  //    enrollment had advertised 9520bb7abf3295ee — so without binding, a
  //    party listens at an address no sender ever writes to. Production does
  //    this in `collectConveyedKeyMaterial`; this test does not yet.
  //
  // Point 2 is mechanical. Point 1 is structural and is the real blocker.
  test('a holder answers another enrollment and the private is filed',
      () async {
    final holder = await enrol('root-holder');
    final seeker = await enrol('root-seeker');

    // Two distinct enrollments, checked rather than assumed. If the fixture
    // handed back the same enrollment twice the request would be the client
    // asking itself, which the substrate declines outright — and this test
    // would read green for the refusal rather than for the answer.
    expect(seeker.enrollmentId, isNot(holder.enrollmentId));
    expect(seeker.kpid, isNot(holder.kpid));

    final holderSharing = AtClientSecretSharing.forClient(holder.client);
    final seekerSharing = AtClientSecretSharing.forClient(seeker.client);
    await holderSharing.register();
    await seekerSharing.register();

    // Distinctive bytes rather than zeros: a filing bug that wrote the wrong
    // buffer would still produce 32 plausible bytes, and this makes the
    // comparison at the end mean something.
    final rootPrivate =
        Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 11) % 256));
    holderSharing.secretStore.putIfNewer(Secret(
      namespace: namespace,
      name: PqSigningRoot.secretName,
      value: base64Encode(rootPrivate),
    ));

    final seekerKeys = InMemoryAtKeysIo();
    await seekerKeys.write(atSign, AtKeys());
    final seekerRoot = PqSigningRoot(seeker.client, keysIo: seekerKeys);

    // The precondition. Without it the filing check at the end could be
    // satisfied by a private that was already there.
    expect(await seekerRoot.privateHalf(atSign), isNull,
        reason: 'the seeker must genuinely lack the root, or this proves '
            'nothing about acquiring it');

    final asked = await seekerRoot.requestPrivateIfAbsent(
      isFullyPrivileged: () async => true,
      sharing: seekerSharing,
      namespace: namespace,
    );
    expect(asked, greaterThan(0),
        reason: 'the request must reach at least one key package — this is '
            'the enumeration that only an APKAM-authenticated connection can '
            'perform, and it is the half the single-client harness could not '
            'reach at all');

    // The holder comes online and answers. Authorizing the requester is the
    // step that needs APKAM on THIS side too.
    await holderSharing.sweepOnce(fromRemote: true);

    // The seeker collects the answer.
    await seekerSharing.sweepOnce(fromRemote: true);

    final received = seekerSharing.secretStore
        .listSecrets(namespace: namespace)
        .where((s) => s.name == PqSigningRoot.secretName)
        .firstOrNull;
    expect(received, isNotNull,
        reason: 'the answer must come back over the envelope channel, sealed '
            'to the requester\'s key package');

    // The part that matters most: it reaches the KEYFILE, not just the secret
    // store. That store is a transit buffer and in-memory by design, so a
    // private stopping there would be gone at the next start — and the root,
    // being immutable and non-rotating, cannot be re-minted to recover.
    expect(
        await seekerRoot.filePendingPrivate(
            atSign, seekerSharing.secretStore.listSecrets()),
        isTrue);
    expect(await seekerRoot.privateHalf(atSign), rootPrivate,
        reason: 'byte-for-byte what the holder had. A private that arrived '
            'mangled would anchor this enrollment to a root the atSign does '
            'not have, which verifies as tampering rather than as an error');
  },
      skip: 'blocked: AtClientImpl caches clients by atSign alone, so two '
          'enrollments of one atSign cannot have distinct clients in one '
          'process — see the note above and decisions 32');
}
