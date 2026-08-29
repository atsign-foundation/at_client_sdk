// The nskey surface and the substrate are @experimental; driving them is the
// point of this file.
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
/// The two halves are each proven elsewhere and never together, which is why
/// this exists. `pq_native_app_enrollment_test.dart` shows an ML-DSA
/// enrollment is post-quantum from birth, but it is fully privileged and reads
/// nothing. `enrollment_namespace_gate_test.dart` shows the atServer refusing a
/// scoped enrollment the envelope channel of a namespace it was not granted,
/// but its enrollment authenticates with RSA-2048 and never builds a client, so
/// nothing there reads self data at all.
///
/// What is missing between them is one enrollment doing both: authenticating
/// under ML-DSA, opening this atSign's own data in its granted namespace, and
/// being refused the other namespace's keys on the same connection. A scoped
/// enrollment that could collect every namespace's privates would make the
/// grant advisory, and a grant that also withheld the namespace it DID give
/// would make approval-time conveyance impossible — so both arms are needed to
/// say the boundary is a boundary rather than a wall.
void main() {
  final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'] as String;

  /// Unique per run, and it does two jobs. The atServer refuses a second
  /// enrollment carrying an already-approved `(appName, deviceName)`, and an
  /// nskey mint takes a `_nskeylock` whose ttl also refuses a rotation — so
  /// fixed namespaces would pass on a fresh virtualenv and fail on the next
  /// run against the same one.
  final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// The namespace the enrollment is granted, and the one it is not.
  final granted = 'grantpq$runId';
  final withheld = 'heldpq$runId';

  late AtClient approver;

  setUpAll(() async {
    // ⚠️ The approver needs an AtKeysIo. Approval conveys the approver's FILED
    // nskey privates, read from AtKeys — without a keyfile the minted private
    // is never filed, and the enrollment below starts holding nothing and has
    // to pull it from a peer instead.
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    // The approver stays on the migration posture: what it is willing to write
    // is what the enrollment handshake depends on, and posture is per-client.
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
    // @alice on the nskey data path, with a generation for each namespace. The
    // withheld one is minted too: the refusal below has to be about the grant,
    // not about a namespace that does not exist.
    final ring = PublishedNskeyKeyRing(approver);
    approver.getPreferences()!.crypto = CryptoConfig.nskey(keyRing: ring);
    await ring.mintAndPublish(granted);
    await ring.mintAndPublish(withheld);

    // @alice's own data, in the granted namespace, sealed to @alice's own
    // namespace key.
    final selfKey = AtKey()
      ..key = 'selfdata$runId'
      ..namespace = granted
      ..sharedBy = atSign
      ..sharedWith = atSign;
    const selfValue = 'alice reads her own data from a scoped device';
    expect(await approver.put(selfKey, selfValue), true);

    // Verified rather than assumed: this really is the nskey data path. A
    // legacy write is readable by every enrollment of the atSign for an
    // entirely different reason — the self encryption key is atSign-wide — and
    // the read below would then say nothing about namespace scoping.
    final asWritten = await approver.get(selfKey);
    expect(asWritten.metadata?.appMetadata?.providerId,
        symmetricAesGcmCryptoProviderId,
        reason: 'the self record must be on the nskey data path, or the read '
            'below is green for the atSign-wide self encryption key rather '
            'than for a namespace private this enrollment was conveyed');

    // The enrollment: ML-DSA APKAM keypair, granted one namespace.
    //
    // The preference is at the migration posture with ONE axis moved — the
    // authentication key algorithm. That is the axis `retrofitIsDue` compares
    // against what the enrollment holds, so naming it here is what stops the
    // client discarding this enrollment and minting another; and leaving the
    // rest of the posture alone keeps this client out of the seeding and
    // signing-key business, which would take mint locks it has no reason to
    // touch.
    final enrolleeKeysIo = InMemoryAtKeysIo();
    await enrolleeKeysIo.write(atSign, AtKeys());
    final preference = TestUtils.getPreference(atSign,
        posture: legacyPlusPqProviders,
        authenticationKeyAlgorithm: SigningAlgoType.mldsa65)
      // A store of its own. Two clients of one atSign sharing a storage path
      // share their keystore, and this one is supposed to hold only what its
      // own approval conveyed.
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
    );

    // ⚠️ The PQ startup steps are fire-and-forget, and the one that matters
    // here is the sweep that files an arriving nskey private out of the
    // secret-sharing transit buffer. Without this wait the read below runs
    // against a client whose approval-time conveyance is sitting in a store it
    // has not drained yet, and fails with "no nskey private held … or has not
    // yet received that generation" — which is the truth, and not the claim.
    // `startupComplete` is the documented handle and never completes with an
    // error, so it cannot turn a step's failure into a hang.
    await (scoped.client as AtClientImpl).pqBootstrap!.startupComplete;

    // It authenticates POST-QUANTUM, and it is this enrollment that does.
    // `enrolAndAuthenticate` has already PKAM-authenticated by now, so the
    // question left is which key material that used.
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

    // And it really is SCOPED. Checked rather than assumed: if the atServer
    // widened the grant, the two arms below would be a comparison of one case
    // with itself and would read green.
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

    // The first half of the clause: it decrypts @alice's own data in the
    // namespace it holds. Read from the atServer rather than its own store —
    // this client has a store of its own and never saw the write.
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
    // enrollment's key package, differing only in namespace.
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

    // The control, and it is not drawn from the property under test: both
    // records exist and a client authorised for everything reads them on the
    // very verb the refusal names. Without it, "the scoped enrollment could
    // not read it" is equally explained by the record never having been
    // written.
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

    // The negative arm. Same client, same connection, same verb — only the
    // namespace differs. Matched on the REASON rather than merely on throwing:
    // a bare throwsA is satisfied by a dropped connection or a malformed key,
    // and this would then be green for the absence of an answer.
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
