// The substrate is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart'
    show AtChopsImpl, AtChopsKeys, AtEncryptionKeyPair, AtPkamKeyPair;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/service/enrollment_service_impl.dart'
    show EnrollmentServiceImpl;
import 'package:at_commons/at_builders.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'test_utils.dart';

/// The namespace boundary a scoped enrollment is held to, enforced by the
/// atServer.
///
/// `acceptance.md` UC-A2.3 is explicit that this boundary is *"enforced at the
/// atServer `__ssenv` namespace-delivery gate, not by a client-side refusal
/// alone"*, and the distinction is the whole point: `shareAllSecretsWith`
/// filters by approved namespace before sending, but a filter in the sender is
/// worth nothing against a client that simply asks for the record itself. Only
/// the atServer can actually stop that, and until this ran, nothing had watched
/// it try.
///
/// The control matters more than the refusal here. A scoped enrollment failing
/// to read a record proves nothing on its own — the record might not exist, the
/// name might be wrong, the connection might be broken. So the approver reads
/// the same record back on the same atSign, and the two arms differ in exactly
/// one thing: which enrollment is asking.
void main() {
  late AtClient atClient;
  late String atSign;
  const namespace = 'buzz';

  /// The namespace the scoped enrollment is authorised for, and the one it is
  /// not. Unique per run so a previous run's grants cannot make this pass.
  final granted = 'gr${DateTime.now().microsecondsSinceEpoch}';
  final withheld = 'wh${DateTime.now().microsecondsSinceEpoch}';

  setUpAll(() async {
    atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final keysIo = InMemoryAtKeysIo();
    await keysIo.write(atSign, AtKeys());
    final manager =
        await TestUtils.initAtClient(atSign, namespace, atKeysIo: keysIo);
    atClient = manager.atClient;
    await AtClientSecretSharing.forClient(atClient).register();
  });

  /// Enrols a **scoped** enrollment authorised for [namespaces], approves it,
  /// and returns what the enrolling side keeps.
  Future<
      ({
        String enrollmentId,
        String kpid,
        AtKeys keys,
        Map<String, dynamic>? grantedNamespaces
      })> enrolScoped(Map<String, String> namespaces) async {
    final otp = (await atClient.getOTP()).response;

    Map<String, dynamic>? built;
    AtKeys? enrolleeKeys;
    final build = enrollmentKeyPackageBuilder(atSign);

    final response = await AtEnrollment.create().submit(
      AtEnrollmentRequest.pq(
        atSign: atSign,
        appName: namespace,
        deviceName: 'scoped-${Uuid().v4().hashCode}',
        namespaces: namespaces,
        otp: otp,
        metadataBuilder: (keysIo) async {
          built = await build(keysIo);
          enrolleeKeys = await keysIo.read(atSign);
          return built;
        },
        apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(atSign),
      ),
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    final payload = SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
    return (
      enrollmentId: response.enrollmentId,
      kpid: ((payload['keys'] as List).single as Map)['kid'] as String,
      keys: enrolleeKeys!,
      grantedNamespaces:
          (await atClient.enrollmentService!.fetchEnrollmentRequests())
              .where((e) => e.enrollmentId == response.enrollmentId)
              .firstOrNull
              ?.namespace,
    );
  }

  test(
      'a scoped enrollment cannot read the envelope channel of a namespace '
      'it was not granted', () async {
    final scoped = await enrolScoped({granted: 'rw'});

    // Checked, not assumed. If the atServer widened the grant, the two arms
    // below would be a comparison of one case with itself, and it would read
    // green — the same trap the privileged-vs-scoped test upstream guards
    // against.
    expect(EnrollmentServiceImpl.isFullyPrivileged(scoped.grantedNamespaces),
        isFalse,
        reason: 'this must be a SCOPED enrollment; a privileged one is '
            'authorised for everything and would read both records legally');
    expect(scoped.grantedNamespaces?.keys, contains(granted),
        reason: 'and it must actually hold the namespace it is meant to be '
            'allowed, or the positive arm below proves nothing either');
    expect(scoped.grantedNamespaces?.keys, isNot(contains(withheld)));

    // Two envelope-shaped records on the same atSign, addressed to this
    // enrollment's key package, differing only in namespace.
    AtKey envelope(String ns) => AtKey()
      ..key = 'probe${Uuid().v4().hashCode}.${scoped.kpid}.__ssenv'
      ..namespace = ns
      ..sharedBy = atSign
      ..metadata = Metadata();

    final allowed = envelope(granted);
    final forbidden = envelope(withheld);
    for (final key in [allowed, forbidden]) {
      await atClient.getRemoteSecondary()!.executeVerb(
          UpdateVerbBuilder()
            ..atKey = key
            ..value = 'envelope-payload');
    }

    // Control, and the assertion the refusal below depends on: BOTH records
    // exist and are readable by a client authorised for everything. Without
    // this, "the scoped enrollment could not read it" is equally explained by
    // the record never having been written.
    for (final key in [allowed, forbidden]) {
      expect(
          await atClient
              .getRemoteSecondary()!
              .executeCommand('llookup:${key.toString()}\n', auth: true),
          contains('envelope-payload'),
          reason: 'the approver must be able to read ${key.namespace}, or the '
              'scoped enrollment\'s failure below is an absent record rather '
              'than a gate');
    }

    // Now ask as the scoped enrollment. Chops from the APKAM keypair alone —
    // PKAM needs nothing else, and this enrollment has nothing else yet.
    final enrolleeLookup =
        AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort)
          ..enrollmentId = scoped.enrollmentId
          ..atChops = AtChopsImpl(AtChopsKeys.create(
            AtEncryptionKeyPair.create(
                scoped.keys.defaultEncryptionPublicKey!.toString(), ''),
            AtPkamKeyPair.create(scoped.keys.apkamPublicKey!.toString(),
                scoped.keys.apkamPrivateKey!.toString()),
          ));

    try {
      expect(
          await enrolleeLookup.pkamAuthenticate(
              enrollmentId: scoped.enrollmentId),
          true,
          reason: 'the enrollment is approved, so it must authenticate — an '
              'enrollment that cannot connect would fail both arms below and '
              'tell us nothing about namespaces');

      // The positive arm. Its namespace was granted, so the channel is open.
      expect(
          await enrolleeLookup.executeCommand('llookup:${allowed.toString()}\n',
              auth: true),
          contains('envelope-payload'),
          reason: 'a scoped enrollment must still receive envelopes in the '
              'namespace it WAS granted, or the gate is not a boundary but a '
              'wall and approval-time conveyance could never reach it');

      // The negative arm. Same client, same connection, same verb — only the
      // namespace differs.
      // Matched on the reason, not merely on throwing: a bare throwsA would be
      // satisfied by a dropped connection or a malformed key, and this test
      // would then be green for the absence of an answer rather than for the
      // gate. The atServer names the enrollment and the key it refused, which
      // is exactly what makes the refusal attributable.
      await expectLater(
          enrolleeLookup.executeCommand('llookup:${forbidden.toString()}\n',
              auth: true),
          throwsA(predicate((e) =>
              e is AtLookUpException &&
              '$e'.contains('not authorized to llookup') &&
              '$e'.contains(scoped.enrollmentId) &&
              '$e'.contains(withheld))),
          reason: 'the atServer must refuse this, and refuse it as an '
              'authorization decision naming this enrollment and this '
              'namespace. A client-side filter in the sender cannot stop an '
              'enrollment that simply asks for the record, so if this '
              'succeeds the namespace boundary is advisory and a scoped '
              'enrollment can collect every namespace\'s privates');
    } finally {
      await enrolleeLookup.close();
    }
  });
}
