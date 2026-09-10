// The substrate is @experimental; driving it is the point here.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

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

/// The namespace boundary a scoped enrollment is held to — UC-A2.3 — enforced
/// at the atServer `__ssenv` namespace-delivery gate rather than by a
/// client-side refusal alone.
///
/// Every refusal is paired with the approver reading the same record on the
/// same atSign, so the two arms differ in exactly one thing: which enrollment
/// is asking.
void main() {
  TestUtils.isolateStorage('enrollment_namespace_gate_test');
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
    final manager = await TestUtils.initAtClient(atSign, namespace,
        atKeysIo: keysIo, posture: legacyPlusPqProviders);
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
        // pq is the key exchange; the enrollment still authenticates with an
        // RSA-2048 APKAM keypair.
        signingAlgo: SigningAlgoType.rsa2048,
      ),
      AtLookupImpl(atSign, 'vip.ve.atsign.zone', TestUtils.rootServerPort),
    );

    await atClient.enrollmentService!
        .approve(EnrollmentRequestDecision.approved(
      atSign: atSign,
      enrollmentId: response.enrollmentId,
      apkamSymmetricKey: AtBytes.fromString(''),
    ));

    final payload =
        SignedEnvelope.fromJson(built!['keyPackage'] as Map).payload as Map;
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

    expect(EnrollmentServiceImpl.isFullyPrivileged(scoped.grantedNamespaces),
        isFalse,
        reason: 'this must be a SCOPED enrollment; a privileged one is '
            'authorised for everything and would read both records legally');
    expect(scoped.grantedNamespaces?.keys, contains(granted),
        reason: 'and it must actually hold the namespace it is meant to be '
            'allowed, or the positive arm below proves nothing either');
    expect(scoped.grantedNamespaces?.keys, isNot(contains(withheld)));

    AtKey envelope(String ns) => AtKey()
      ..key = 'probe${Uuid().v4().hashCode}.${scoped.kpid}.__ssenv'
      ..namespace = ns
      ..sharedBy = atSign
      ..metadata = Metadata();

    final allowed = envelope(granted);
    final forbidden = envelope(withheld);
    for (final key in [allowed, forbidden]) {
      await atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = key
        ..value = 'envelope-payload');
    }

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

      expect(
          await enrolleeLookup.executeCommand('llookup:${allowed.toString()}\n',
              auth: true),
          contains('envelope-payload'),
          reason: 'a scoped enrollment must still receive envelopes in the '
              'namespace it WAS granted, or the gate is not a boundary but a '
              'wall and approval-time conveyance could never reach it');

      // NOTE: matched on the refusal's own wording, not merely on throwing — a
      // bare throwsA is satisfied by a dropped connection or a malformed key.
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

  test(
      'a scoped enrollment can read and write the namespace it was granted, '
      'and neither in the one it was not', () async {
    // Ordinary records rather than the `__ssenv` delivery channel, which could
    // have been special-cased on its own, and both verbs, because read and
    // write are two authorisations the atServer answers separately.
    final scoped = await enrolScoped({granted: 'rw'});

    expect(EnrollmentServiceImpl.isFullyPrivileged(scoped.grantedNamespaces),
        isFalse,
        reason: 'a privileged enrollment is authorised for everything and '
            'would pass both arms legally, making this a comparison of one '
            'case with itself');
    expect(scoped.grantedNamespaces?.keys, contains(granted));
    expect(scoped.grantedNamespaces?.keys, isNot(contains(withheld)));

    AtKey record(String ns) => AtKey()
      ..key = 'dataprobe${Uuid().v4().hashCode}'
      ..namespace = ns
      ..sharedBy = atSign
      ..metadata = Metadata();

    final allowed = record(granted);
    final forbidden = record(withheld);
    for (final key in [allowed, forbidden]) {
      await atClient.getRemoteSecondary()!.executeVerb(UpdateVerbBuilder()
        ..atKey = key
        ..value = 'data-payload');
    }

    for (final key in [allowed, forbidden]) {
      expect(
          await atClient
              .getRemoteSecondary()!
              .executeCommand('llookup:${key.toString()}\n', auth: true),
          contains('data-payload'),
          reason: 'the approver must read ${key.namespace}, or the scoped '
              'enrollment\'s failure below is an absent record rather than a '
              'gate');
    }

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
          reason: 'an enrollment that cannot connect fails every arm below '
              'and says nothing about namespaces');

      expect(
          await enrolleeLookup.executeCommand('llookup:${allowed.toString()}\n',
              auth: true),
          contains('data-payload'),
          reason: 'a scoped enrollment must be able to USE the namespace it '
              'was granted, or the grant buys it nothing and the refusal '
              'below is a wall rather than a boundary');

      final written = await enrolleeLookup.executeCommand(
          'update:${record(granted).toString()} written-by-scoped\n',
          auth: true);
      expect(written, startsWith('data:'),
          reason: 'and it must be able to write there too — the row says '
              'read/write, and an enrollment that can only read would satisfy '
              'a test asserting only the read');

      // NOTE: matched on the refusal's own wording, including the verb, which
      // is what keeps the read and write arms distinguishable.
      await expectLater(
          enrolleeLookup.executeCommand('llookup:${forbidden.toString()}\n',
              auth: true),
          throwsA(predicate((e) =>
              e is AtLookUpException &&
              '$e'.contains('not authorized to llookup') &&
              '$e'.contains(scoped.enrollmentId) &&
              '$e'.contains(withheld))),
          reason: 'the atServer must refuse the READ as an authorization '
              'decision naming this enrollment and this namespace');

      await expectLater(
          enrolleeLookup.executeCommand(
              'update:${record(withheld).toString()} written-by-scoped\n',
              auth: true),
          throwsA(predicate((e) =>
              e is AtLookUpException &&
              '$e'.contains('not authorized to update') &&
              '$e'.contains(scoped.enrollmentId) &&
              '$e'.contains(withheld))),
          reason: 'and the WRITE separately, under its own verb. A gate that '
              'refused reads and accepted writes would let a scoped '
              'enrollment plant records in a namespace it cannot see, which '
              'is worse than reading one');
    } finally {
      await enrolleeLookup.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
