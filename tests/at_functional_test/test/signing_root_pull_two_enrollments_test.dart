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
import 'package:at_client/src/service/enrollment_service_impl.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The signing-root pull between two real APKAM enrollments.
///
/// This is the route an enrollment takes when it was offline during the wave
/// that conveyed the root: the root is atSign-level and carries no namespace,
/// so it never rides the `enroll:listns` fan-out, and nothing re-mints a root
/// that is already published, so no later event can produce a replacement.
///
/// It needs two genuine enrollments and nothing less. The pull authenticates
/// on **both** sides — the requester to enumerate holders, the responder to
/// authorize the requester before answering — and both go through
/// `enroll:listns`, which the atServer answers only for an APKAM-authenticated
/// connection. A client using the atSign's own keys is refused at either end,
/// which is why the earlier single-client attempt could not reach this and why
/// `enrolAndAuthenticate` exists.
///
/// On secondAtSign, which nothing else roots, because the conveyed private
/// must be THE root private: filing checks correspondence against the
/// published record, so the holder has to hold the real key — this file mints
/// the root itself and keeps the private. (On firstAtSign the chain-link test
/// may have minted first, into an in-memory keyfile another isolate owned.)
///
/// This could not run at all until `AtClientImpl`'s instance cache was keyed by
/// `(atSign, enrollmentId)` rather than the atSign alone. Before that, every
/// "enrollment" here was `identical` to the approver's client and to the other
/// enrollment, so the request was a client asking itself over a connection that
/// carried no enrollment id.
void main() {
  late AtClient approver;
  late String atSign;
  late Uint8List rootPrivate;
  const namespace = 'buzz';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    approver = manager.atClient;
    await AtClientSecretSharing.forClient(approver).register();

    // Mint the root this test's holder will serve. Owner keys: fully
    // privileged by construction, and the private lands in this keysIo.
    final approverRoot = PqSigningRoot(approver, keysIo: keysIo);
    await approverRoot.mintIfAbsent(isFullyPrivileged: true);
    final held = await approverRoot.privateHalf(atSign);
    expect(held, isNotNull,
        reason: 'the holder below can only serve the REAL root private — '
            'filing checks correspondence against the published record, so a '
            'made-up buffer no longer stands in for it. If this fails on a '
            're-run, the virtualenv was not recycled: the record survives '
            'from the earlier run and the private died with its isolate');
    rootPrivate = held!;
  });

  // Unique per run. The atServer refuses a second enrollment carrying an
  // (appName, deviceName) pair that already has one approved, so fixed names
  // pass on a fresh virtualenv and collide on every re-run against it — which
  // is exactly what happened the first time this went green.
  final runId = DateTime.now().microsecondsSinceEpoch;

  /// Fully privileged by default: the root vouches for every enrollment on the
  /// atSign, so only that class may hold it — and a holder refuses to serve it
  /// to anything else, which is what the scoped arm at the end checks.
  Future<EnrolledClient> enrol(String device,
          {Map<String, String>? namespaces}) =>
      enrolAndAuthenticate(
        approver: approver,
        atSign: atSign,
        namespace: namespace,
        preference: TestUtils.getPreference(atSign),
        rootDomain: 'vip.ve.atsign.zone',
        rootPort: TestUtils.rootServerPort,
        deviceName: '$device-$runId',
        namespaces: namespaces ??
            {'*': 'rw', '__manage': 'rw', namespace: 'rw'},
      );

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

    // And both are genuinely privileged, read off the atServer's own record.
    // A holder serves per-enrollment material only to that class, so if the
    // grant had been trimmed this would fail for the refusal rather than for
    // anything about conveyance.
    final granted = await approver.enrollmentService!.fetchEnrollmentRequests();
    for (final id in [holder.enrollmentId, seeker.enrollmentId]) {
      expect(
          EnrollmentServiceImpl.isFullyPrivileged(granted
              .where((e) => e.enrollmentId == id)
              .firstOrNull
              ?.namespace),
          isTrue,
          reason: 'the pull is only legitimate between enrollments entitled '
              'to hold the root');
    }

    final holderSharing = AtClientSecretSharing.forClient(holder.client);
    final seekerSharing = AtClientSecretSharing.forClient(seeker.client);
    await holderSharing.register();
    await seekerSharing.register();

    // The holder holds the real private, as any genuine holder would.
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
    // already published, is never re-minted to recover.
    expect(
        await seekerRoot.filePendingPrivate(
            atSign, seekerSharing.secretStore.listSecrets()),
        isTrue);
    expect(await seekerRoot.privateHalf(atSign), rootPrivate,
        reason: 'byte-for-byte what the holder had. A private that arrived '
            'mangled would anchor this enrollment to a root the atSign does '
            'not have, which verifies as tampering rather than as an error');
  });

  test('a scoped enrollment asking for the root is not served', () async {
    final holder = await enrol('gate-holder');
    final scoped = await enrol('gate-scoped', namespaces: {namespace: 'rw'});

    final holderSharing = AtClientSecretSharing.forClient(holder.client);
    final scopedSharing = AtClientSecretSharing.forClient(scoped.client);
    await holderSharing.register();
    await scopedSharing.register();

    // Checked, not assumed — otherwise this could be comparing a privileged
    // case with itself and reading green for the wrong reason.
    final granted = await approver.enrollmentService!.fetchEnrollmentRequests();
    expect(
        EnrollmentServiceImpl.isFullyPrivileged(granted
            .where((e) => e.enrollmentId == scoped.enrollmentId)
            .firstOrNull
            ?.namespace),
        isFalse);

    holderSharing.secretStore.putIfNewer(Secret(
      namespace: namespace,
      name: PqSigningRoot.secretName,
      value: base64Encode(rootPrivate),
    ));

    // The scoped enrollment asks anyway — the requester-side guard is a
    // courtesy, and a compromised or modified client simply omits it. What
    // must hold is that the HOLDER refuses.
    await scopedSharing
        .requestSecretsFromNamespace(namespace, names: [PqSigningRoot.secretName]);
    await holderSharing.sweepOnce(fromRemote: true);
    await scopedSharing.sweepOnce(fromRemote: true);

    expect(
        scopedSharing.secretStore
            .listSecrets(namespace: namespace)
            .where((s) => s.name == PqSigningRoot.secretName),
        isEmpty,
        reason: 'namespace authorization is the only other check on the answer '
            'path, and this enrollment passes it — so without a privilege gate '
            'any enrollment approved for any namespace the holder serves could '
            'ask for the key that vouches for every enrollment on the atSign, '
            'and be handed it');
  });

  test('bytes that do not correspond to the published root are refused',
      () async {
    // What a compromised or buggy holder might serve. Before the
    // correspondence check, exactly this buffer was filed byte-for-byte and
    // read back as "the root private" — permanently, since nothing re-mints
    // a published root and the heal that clears it needs a correct answer to
    // arrive first.
    final fake =
        Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 11) % 256));

    final keys = InMemoryAtKeysIo();
    await keys.write(atSign, AtKeys());
    final root = PqSigningRoot(approver, keysIo: keys);

    expect(
        await root.filePendingPrivate(atSign, [
          Secret(
            namespace: namespace,
            name: PqSigningRoot.secretName,
            value: base64Encode(fake),
          )
        ]),
        isFalse,
        reason: 'filing verifies the arriving private against the root record '
            'this live atServer serves — the check runs against the real '
            'published key, not a fixture');
    expect(await root.privateHalf(atSign), isNull);
  });
}
