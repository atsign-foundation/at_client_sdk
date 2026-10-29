import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, EnvelopeType, signEnvelope;
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/recorded_logs.dart';
import 'test_utils/test_keypairs.dart';

/// Collecting the `apkamSymmetricKey` an approver sealed to a new enrollment.
///
/// Every rejection on this path has to be a **skip**: an atSign's clients may
/// have several envelopes in flight at once, and one this enrollment cannot use
/// says nothing about the one it is waiting for.
void main() {
  const atSign = '@alice';
  const kpid = 'kpid-1';

  /// Files a key package — **both** halves under one keyId, which is what
  /// `enrollmentKeyPackageBuilder` produces and what identifies a package as
  /// distinct from an nskey private, which is filed under the same part type
  /// but arrives alone.
  void fileKeyPackage(
    AtKeys keys, {
    required String keyId,
    String? enrollmentId,
    int seed = 0,
    DateTime? createdAt,
  }) {
    final at = createdAt ?? DateTime.now().toUtc();
    keys
      ..addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.privateDecapsulation,
        algorithm: CryptographicMaterialAlgorithm.xWing,
        bytes: AtBytes(
            Uint8List.fromList(List<int>.generate(32, (i) => i + seed))),
        createdAt: at,
      ))
      ..addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        role: CryptographicMaterialRole.publicEncapsulation,
        algorithm: CryptographicMaterialAlgorithm.xWing,
        bytes: AtBytes(
            Uint8List.fromList(List<int>.generate(32, (i) => i + seed + 100))),
        createdAt: at,
      ));
  }

  AtKeys withKeyPackage() {
    final keys = AtKeys();
    fileKeyPackage(keys, keyId: kpid);
    return keys;
  }

  const envelopeKey = '@alice:abc.$kpid.__ssenv.myapp@alice';

  /// An envelope for this kpid, signed by [signer] as an approver signs one:
  /// it parses, so the resolver goes on to look up [signer]'s `_apsk`.
  String signedBy(String signer) {
    final pkam = pkamKeyPairFor(atSign, signer);
    return jsonEncode(signEnvelope(
      {'toKpid': kpid},
      keys: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.rsa2048,
            publicKey: pkam.atPublicKey.publicKey,
            privateKey: pkam.atPrivateKey.privateKey)
      ],
      type: EnvelopeType.secretEnvelope,
      enrollmentId: signer,
    ).toJson());
  }

  /// A lookup that finds [signedBy]'s envelope from [signer] and answers the
  /// `_apsk` lookup for [signer] with [apsk], or throws the atServer's AT0015
  /// when [apsk] is null, which is what a revoked signer's key lookup returns.
  MockAtLookUp lookupWith({required String signer, String? apsk}) {
    final envelope = signedBy(signer);
    final lookUp = MockAtLookUp();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      final command = inv.positionalArguments[0] as String;
      if (command.startsWith('scan')) {
        return 'data:${jsonEncode([envelopeKey])}';
      }
      if (command.contains('_apsk.$signer')) {
        if (apsk == null) {
          throw AtLookUpException(
              'AT0015',
              'key not found : public:_apsk.$signer.a.__e$atSign does not '
                  'exist in keystore');
        }
        return 'data:$apsk';
      }
      if (command.contains(envelopeKey)) return 'data:$envelope';
      return null;
    });
    return lookUp;
  }

  /// Whether [lookUp] was asked for [signer]'s `_apsk`.
  void verifyApskLookedUp(MockAtLookUp lookUp, String signer) => verify(() =>
      lookUp.executeCommand(any(that: contains('_apsk.$signer.a.__e')),
          auth: any(named: 'auth'))).called(greaterThan(0));

  final logs = RecordedLogs();

  setUpAll(() {
    logs.installOn();
    registerFallbackValue('');
  });

  test('an envelope whose signer has no _apsk is skipped, not fatal', () async {
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));
    final lookUp = lookupWith(signer: 'unpublished-enrollment');

    // NOTE: the `_apsk` lookup for a signer with no key answers AT0015, which
    // AtLookupImpl throws rather than returning null — uncaught, it escapes
    // the skip and takes the whole enrollment down.
    await expectLater(
        resolve(withKeyPackage(), lookUp).toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))),
        reason: 'an envelope whose signer has no key is not from an approved '
            'enrollment and is skipped. Propagating the lookup error instead '
            'means one such envelope fails every later enrollment that walks '
            'past it');
    verifyApskLookedUp(lookUp, 'unpublished-enrollment');
  });

  test(
      'a revoked signer is looked up by the enrollment its signature names, '
      'and skipped the same way', () async {
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));
    final lookUp = lookupWith(signer: 'revoked-enrollment');

    await expectLater(
        resolve(withKeyPackage(), lookUp).toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))),
        reason: 'the atServer moves a revoked enrollment\'s _apsk out from '
            'under its approved address, so the lookup answers AT0015');
    verifyApskLookedUp(lookUp, 'revoked-enrollment');
  });

  test('and a signer whose _apsk does not verify is skipped too', () async {
    // NOTE: the key served is a real one, another enrollment's, so the
    // refusal is the signature's rather than a malformed key's.
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: const Duration(milliseconds: 200),
        pollInterval: const Duration(milliseconds: 50));
    final lookUp = lookupWith(
        signer: 'live-enrollment',
        apsk: pkamKeyPairFor(atSign, 'other-enrollment').atPublicKey.publicKey);

    await expectLater(
        resolve(withKeyPackage(), lookUp).toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('No conveyed apkamSymmetricKey arrived'))));
    verifyApskLookedUp(lookUp, 'live-enrollment');
  });

  const approver = 'approver-enrollment';
  const conveyed = 'the-apkam-symmetric-key';

  /// [withKeyPackage]'s envelope sealed to the key package's real public half
  /// for `myapp` under a body naming [approver] as its sender, and signed by
  /// [signer].
  Future<String> approverEnvelope({String signer = approver}) async {
    final kem = XWingPureDartAlgo.instance;
    final recipient = await kem
        .keyPairFromSeed(Uint8List.fromList(List<int>.generate(32, (i) => i)));
    final info = PairwiseSecretSharing.sealInfoFor(
        fromEnrollmentId: approver,
        fromKpid: 'kpid-approver',
        toKpid: kpid,
        appNamespace: 'myapp');
    final sealed = await pqSeal(
        kem,
        recipient.publicKey,
        Uint8List.fromList(utf8.encode(jsonEncode({
          'kind': PairwiseSecretSharing.secretPayloadKind,
          'name': enrollmentApkamSymmetricKeySecretName,
          'value': conveyed,
        }))),
        info: info);
    final pkam = pkamKeyPairFor(atSign, signer);
    return jsonEncode(signEnvelope(
      SecretEnvelope(
        fromKpid: 'kpid-approver',
        fromEnrollmentId: approver,
        toKpid: kpid,
        appNamespace: 'myapp',
        suite: SecretSharingAlgos.xWingRfc9180,
        kid: kpid,
        sealed: base64Encode(sealed),
      ).toJson(),
      keys: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.rsa2048,
            publicKey: pkam.atPublicKey.publicKey,
            privateKey: pkam.atPrivateKey.privateKey)
      ],
      type: EnvelopeType.secretEnvelope,
      enrollmentId: signer,
    ).toJson());
  }

  /// A lookup whose scan finds [value] at [key] and whose `_apsk` lookup
  /// answers with [signer]'s real public key.
  MockAtLookUp serving(String key, String value, {String signer = approver}) {
    final lookUp = MockAtLookUp();
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((inv) async {
      final command = inv.positionalArguments[0] as String;
      if (command.startsWith('scan')) return 'data:${jsonEncode([key])}';
      if (command.contains('_apsk.$signer')) {
        return 'data:${pkamKeyPairFor(atSign, signer).atPublicKey.publicKey}';
      }
      if (command.contains(key)) return 'data:$value';
      return null;
    });
    return lookUp;
  }

  group('a genuinely sealed and signed envelope', () {
    test(
        'is skipped before its _apsk is looked up when its signer is not an '
        'enrollment id', () async {
      final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
          timeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50));
      const key = 'msg.0.$kpid.__ssenv.myapp@alice';

      for (final signer in ['approver\n', 'appro.ver', 'appro:ver']) {
        final lookUp = serving(key, await approverEnvelope(signer: signer),
            signer: signer);
        await expectLater(resolve(withKeyPackage(), lookUp).toList(),
            throwsA(isA<StateError>()),
            reason: 'a signer of ${signer.length} characters');
        verifyNever(() => lookUp.executeCommand(any(that: contains('_apsk')),
            auth: any(named: 'auth')));
      }

      // NOTE: positive control — the same envelope from an enrollment id is
      // looked up and collected.
      final control = serving(key, await approverEnvelope());
      expect(await resolve(withKeyPackage(), control).first, conveyed);
      verify(() => control.executeCommand(
          any(that: contains('_apsk.$approver.')),
          auth: any(named: 'auth'))).called(greaterThan(0));
    });

    test('is collected where its approver addressed it', () async {
      // NOTE: the positive control for every skip in this file, none of which
      // otherwise shows that anything is ever collected.
      final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
          timeout: const Duration(seconds: 5),
          pollInterval: const Duration(milliseconds: 50));
      expect(
          await resolve(
                  withKeyPackage(),
                  serving('msg.0.$kpid.__ssenv.myapp@alice',
                      await approverEnvelope()))
              .first,
          conveyed);
    });

    test('is skipped when it sits under a namespace its approver did not sign',
        () async {
      final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
          timeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50));
      await expectLater(
          resolve(
                  withKeyPackage(),
                  serving('msg.0.$kpid.__ssenv.otherapp@alice',
                      await approverEnvelope()))
              .toList(),
          throwsA(isA<StateError>().having((e) => '$e', 'message',
              contains('No conveyed apkamSymmetricKey arrived'))));
    });
  });

  group("Given an envelope C seals and signs whose body names A's enrollment",
      () {
    test('when B sweeps, then it is refused, by name', () async {
      const signerC = 'other-enrollment';
      const key = 'msg.0.$kpid.__ssenv.myapp@alice';
      final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
          timeout: const Duration(milliseconds: 200),
          pollInterval: const Duration(milliseconds: 50));
      logs.records.clear();

      await expectLater(
          resolve(
                  withKeyPackage(),
                  serving(key, await approverEnvelope(signer: signerC),
                      signer: signerC))
              .toList(),
          throwsA(isA<StateError>().having((e) => '$e', 'message',
              contains('No conveyed apkamSymmetricKey arrived'))),
          reason: 'C signed it, and its body names $approver as the sender');
      expect(
          logs.at('WARNING').where((m) => m.contains(key)),
          allOf(
              isNotEmpty,
              everyElement(contains('signer enrollment $signerC does not '
                  'match claimed sender enrollment $approver'))),
          reason: 'C sealed the body under the binding that names $approver, '
              'so only the check of signer against sender refuses it');
    });
  });

  test('AtKeys with no key package cannot be resolved at all', () async {
    final resolve = enrollmentApkamSymmetricKeyResolver(atSign);

    await expectLater(
        resolve(AtKeys(), lookupWith(signer: 'anyone')).toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('no key-establishment decapsulation private key'))),
        reason: 'nothing sealed to this enrollment could be opened, and '
            'polling for half a minute to say so helps nobody. The message '
            'names no single KEM because the lookup accepts any this build '
            'implements — an enrollment minted under either is openable here');
  });

  test('a co-tenant enrollment\'s key package is never adopted', () async {
    final keys = AtKeys();
    fileKeyPackage(keys,
        keyId: 'co-tenant-kpid',
        enrollmentId: 'someone-elses-enrollment',
        seed: 50);
    fileKeyPackage(keys, keyId: kpid);

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(milliseconds: 1),
        pollInterval: Duration(milliseconds: 1));

    await expectLater(
        resolve(keys, lookupWith(signer: 'live-enrollment', apsk: 'whatever'))
            .toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            allOf(contains(kpid), isNot(contains('co-tenant-kpid'))))),
        reason: 'the untagged package is this enrollment\'s; one tagged for '
            'another enrollment is never a candidate');
  });

  test('the package tagged for THIS enrollment wins over an untagged one',
      () async {
    final keys = AtKeys.legacy(enrollmentId: 'mine');
    fileKeyPackage(keys, keyId: 'untagged-kpid', seed: 70);
    fileKeyPackage(keys, keyId: 'mine-kpid', enrollmentId: 'mine');

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(milliseconds: 1),
        pollInterval: Duration(milliseconds: 1));

    await expectLater(
        resolve(keys, lookupWith(signer: 'live-enrollment', apsk: 'whatever'))
            .toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            allOf(contains('mine-kpid'), isNot(contains('untagged-kpid'))))),
        reason: 'a package filed against this enrollment is this '
            'enrollment\'s, whatever else the keyfile carries');
  });

  test(
      'an untagged package still resolves for a keyfile written before '
      'adoption existed', () async {
    // NOTE: a keyfile can carry this enrollment's package untagged, so
    // scoping strictly to the enrollment id would stop it opening anything
    // sealed to it.
    final keys = AtKeys.legacy(enrollmentId: 'mine');
    fileKeyPackage(keys, keyId: kpid);

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign,
        timeout: Duration(milliseconds: 1),
        pollInterval: Duration(milliseconds: 1));

    await expectLater(
        resolve(keys, lookupWith(signer: 'live-enrollment', apsk: 'whatever'))
            .toList(),
        throwsA(
            isA<StateError>().having((e) => '$e', 'message', contains(kpid))),
        reason: 'the untagged package is still this enrollment\'s when nothing '
            'was ever filed under its id');
  });

  test('an nskey private is not mistaken for a key package', () async {
    // NOTE: an nskey private has the same part type but arrives alone;
    // adopting it as the recipient identity would make this enrollment answer
    // at an address it never advertised.
    final keys = AtKeys()
      ..addKey(CryptographicMaterial(
        keyId: 'nskey-private',
        role: CryptographicMaterialRole.privateDecapsulation,
        algorithm: CryptographicMaterialAlgorithm.xWing,
        bytes: AtBytes(Uint8List.fromList(List<int>.generate(32, (i) => i))),
        createdAt: DateTime.now().toUtc(),
      ));

    final resolve = enrollmentApkamSymmetricKeyResolver(atSign);

    await expectLater(
        resolve(keys, lookupWith(signer: 'anyone')).toList(),
        throwsA(isA<StateError>().having((e) => '$e', 'message',
            contains('no key-establishment decapsulation private key'))));
  });
}
