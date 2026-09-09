// The nskey surface and the substrate this file drives are @experimental.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'package:at_auth/at_auth.dart' show AtKeys, InMemoryAtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_functional_test/src/enrolled_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// A namespace-scoped enrollment that authenticates post-quantum, reads the
/// namespace it holds, and is refused the key channel of one it does not.
///
/// One enrollment does all three, on one connection. Both arms are needed to
/// say the boundary is a boundary rather than a wall: an enrollment that could
/// collect every namespace's privates would make the grant advisory, and one
/// refused the namespace it WAS granted could never receive approval-time
/// conveyance.
void main() {
  TestUtils.isolateStorage('pq_scoped_enrollment_self_read_test');
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;

  /// Unique per run: the atServer refuses a second enrollment carrying an
  /// already-approved `(appName, deviceName)`, and an nskey mint holds a
  /// `_nskeylock` whose ttl refuses a rotation, so fixed names would pass on a
  /// fresh virtualenv and fail on the next run against the same one.
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  final granted = 'grantpq$runId';
  final withheld = 'heldpq$runId';

  late AtClient approver;

  setUpAll(() async {
    // NOTE: the approver needs an AtKeysIo. Approval conveys the approver's
    // filed nskey privates, read from AtKeys, so without one the minted
    // private is never filed and the enrollment below starts holding nothing.
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    // Posture is per-client, and what the approver is willing to write is what
    // the enrollment handshake depends on.
    final manager = await TestUtils.initAtClient(atSign, granted,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
    approver = manager.atClient;
    // The approver seals the enrollee's symmetric key to its own key package,
    // so it must have one registered before it can approve anything.
    await AtClientSecretSharing.forClient(approver).register();
  });

  test(
      'UC-A2.1: a scoped ML-DSA enrollment reads its own namespace and is refused the key channel of another',
      timeout: Timeout(Duration(minutes: 5)), () async {
    // A generation for each namespace. The withheld one is minted too: the
    // refusal below has to be about the grant, not about a namespace that does
    // not exist.
    final ring = PublishedNskeyKeyRing(approver);
    approver.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(granted);
    await ring.mintAndPublish(withheld);

    final selfKey = AtKey()
      ..key = 'selfdata$runId'
      ..namespace = granted
      ..sharedBy = atSign
      ..sharedWith = atSign;
    const selfValue = 'alice reads her own data from a scoped device';
    // NOTE: remote-first. The scoped client below reads this from the atServer,
    // and a local-first write only gets there when sync next runs.
    expect(
        await approver.put(selfKey, selfValue,
            putRequestOptions: PutRequestOptions()..useRemoteAtServer = true),
        true);

    // Verified rather than assumed: this really is the nskey data path.
    final asWritten = await approver.get(selfKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true);
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the self record must be on the nskey data path, or the read '
            'below is green for the atSign-wide self encryption key rather '
            'than for a namespace private this enrollment was conveyed');

    // The enrollment: ML-DSA APKAM keypair, granted one namespace, at the
    // migration posture with one axis moved. That axis is what `retrofitIsDue`
    // compares against what the enrollment holds, so naming it here is what
    // stops the client discarding this enrollment and minting another; leaving
    // the rest of the posture alone keeps this client out of the seeding and
    // signing-key business and the mint locks that come with it.
    final enrolleeKeysIo = InMemoryAtKeysIo();
    await enrolleeKeysIo.write(atSign, AtKeys());
    final preference = TestUtils.getPreference(atSign,
        posture: legacyPlusPqProviders,
        authenticationKeyAlgorithm: SigningAlgoType.mldsa65,
        // NOTE: non-empty. An enrollment with no data signing key signs data
        // with its authentication key, and the constructor refuses a
        // non-rsa2048 one there, so an ML-DSA-authenticating enrollment must
        // own a signing key. rsa2048 rather than ML-DSA keeps `_apsk` in the
        // bare form.
        dataSigningKeyAlgorithms: const {SigningAlgoType.rsa2048})
      // A store of its own: two clients of one atSign sharing a storage path
      // share their keystore, and this one holds only what its own approval
      // conveyed.
      ..hiveStoragePath = 'test/hive/client/$atSign/scoped-$runId'
      ..commitLogPath = 'test/hive/client/$atSign/scoped-$runId';

    final scoped = await enrolAndAuthenticate(
      approver: approver,
      atSign: atSign,
      namespace: granted,
      preference: preference,
      rootDomain: 'vip.ve.atsign.zone',
      rootPort: TestUtils.rootServerPort,
      deviceName: 'scoped-$runId',
      namespaces: {granted: 'rw'},
      atKeysIo: enrolleeKeysIo,
      signingAlgo: SigningAlgoType.mldsa65,
      storage: TestUtils.storage,
    );

    // NOTE: the PQ startup steps are fire-and-forget, and the sweep that files
    // an arriving nskey private out of the secret-sharing transit buffer is
    // one of them — without this wait the read below runs against a client
    // that has not drained it yet. `startupComplete` never completes with an
    // error, so it cannot turn a step's failure into a hang.
    await (scoped.client as AtClientImpl).pqBootstrap!.startupComplete;

    // `enrolAndAuthenticate` has already PKAM-authenticated, so what is left is
    // which key material that used.
    expect(scoped.client.enrollmentId, scoped.enrollmentId,
        reason: 'a client running as a DIFFERENT id has retrofitted itself '
            'onto a new enrollment, and the algorithm assertion below would '
            'then be about the replacement rather than about the enrollment '
            'this test approved');
    final enrolleeKeys = await enrolleeKeysIo.read(atSign);
    expect(enrolleeKeys.authenticationAlgorithmFor(scoped.enrollmentId),
        SigningAlgoType.mldsa65,
        reason: 'the enrollment was submitted as mldsa65, so the keyfile must '
            'hold ML-DSA-65 typed authentication material under that id. If it '
            'holds nothing, the algorithm never reached the wire and the '
            'atServer recorded the absent-field default');

    // And it really is scoped: if the atServer widened the grant, the two arms
    // below would compare one case with itself and read green.
    final record = (await approver.enrollmentService!.fetchEnrollmentRequests())
        .where((e) => e.enrollmentId == scoped.enrollmentId)
        .firstOrNull;
    expect(record, isNotNull,
        reason: 'the enrollment must be on the roster, or nothing here is '
            'about what the atServer thinks it granted');
    expect(EnrollmentServiceImpl.isFullyPrivileged(record!.namespace), isFalse,
        reason: 'a privileged enrollment is authorised for everything and '
            'would read both channels legally');
    expect(record.namespace?.keys, contains(granted));
    expect(record.namespace?.keys, isNot(contains(withheld)));

    // The first half: it decrypts this atSign's own data in the namespace it
    // holds. Read from the atServer rather than its own store, which this
    // client has to itself and which never saw the write.
    expect(
        (await scoped.client.get(selfKey,
                getRequestOptions: GetRequestOptions()
                  ..useRemoteAtServer = true))
            .value,
        selfValue,
        reason: 'the scoped enrollment opens the record with the namespace '
            'private its approval conveyed. This is the grant buying it '
            'something: an enrollment that could read nothing would satisfy '
            'the refusal below just as well');

    // The second half: a key request for a namespace it was not granted.
    // Envelope-shaped records on the same atSign, addressed to this
    // enrollment's key package, differing only in the namespace.
    AtKey envelope(String ns) => AtKey()
      ..key = 'probe${Uuid().v4().hashCode}.${scoped.kpid}.__ssenv'
      ..namespace = ns
      ..sharedBy = atSign
      ..metadata = Metadata();

    final allowed = envelope(granted);
    final forbidden = envelope(withheld);
    for (final key in [allowed, forbidden]) {
      await approver.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = key
        ..value = 'envelope-payload');
    }

    // The control, not drawn from the property under test: both records exist
    // and a client authorised for everything reads them on the very verb the
    // refusal names.
    for (final key in [allowed, forbidden]) {
      expect(
          await approver
              .getRemoteSecondary()!
              .executeCommand('llookup:${key.toString()}\n', auth: true),
          contains('envelope-payload'),
          reason: 'the approver must read ${key.namespace}, or the scoped '
              'enrollment\'s failure below is an absent record rather than a '
              'gate');
    }

    // The positive arm, on the scoped enrollment's own connection.
    expect(
        await scoped.client
            .getRemoteSecondary()!
            .executeCommand('llookup:${allowed.toString()}\n', auth: true),
        contains('envelope-payload'),
        reason: 'a scoped enrollment must still receive envelopes in the '
            'namespace it WAS granted, or the gate is not a boundary but a '
            'wall and approval-time conveyance could never reach it');

    // The negative arm: same client, same connection, same verb, only the
    // namespace differs. Matched on the reason rather than merely on throwing,
    // which a dropped connection or a malformed key would also satisfy.
    await expectLater(
        scoped.client
            .getRemoteSecondary()!
            .executeCommand('llookup:${forbidden.toString()}\n', auth: true),
        throwsA(predicate((e) =>
            '$e'.contains('not authorized to llookup') &&
            '$e'.contains(scoped.enrollmentId) &&
            '$e'.contains(withheld))),
        reason: 'the atServer must refuse the key request as an authorization '
            'decision naming this enrollment and this namespace. A '
            'client-side filter in the sender cannot stop an enrollment that '
            'simply asks for the record, so if this succeeds the namespace '
            'boundary is advisory and a scoped enrollment can collect every '
            'namespace\'s privates');
  });
}
