import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_demo_data/at_demo_data.dart';

import 'test_utils/at_keys.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

class MockLookupVerbBuilder extends Fake implements LookupVerbBuilder {}

/// Encrypts [value] under [symmetricKey] exactly as the atServer holds the two
/// keys it releases at approval, so `waitForApproval` has something real to
/// decrypt.
Future<Map<String, String>> serverHeldKey(
    String value, String symmetricKey) async {
  final key = base64Decode(symmetricKey);
  final iv = InitialisationVector.random(16);
  final ciphertext = await AesCtrEncryptionAlgo(key.length)
      .encrypt(Uint8List.fromList(utf8.encode(value)), key, iv: iv);
  return {
    'value': base64Encode(ciphertext),
    'iv': base64Encode(iv.ivBytes),
  };
}

void main() {
  final atSign = '@alice🛠';
  final alice = atSign.toAtsign();

  setUpAll(() {
    AtSignLogger.root_level = 'shout';
    registerFallbackValue(MockLookupVerbBuilder());
  });

  test(
      'A test to verify submitting enrollment to server and verify enrollment status is pending',
      () async {
    AtLookUp mockAtLookUp = MockAtLookUp();
    AtEnrollmentImpl atEnrollmentServiceImpl = AtEnrollmentImpl(mockAtLookUp);

    String encryptionPublicKey = encryptionPublicKeyMap[atSign]!;

    when(() => mockAtLookUp.executeVerb(any(that: LookUpVerbBuilderMatcher())))
        .thenAnswer((_) async => 'data:$encryptionPublicKey');

    when(() => mockAtLookUp.executeCommand(any(that: startsWith('enroll:'))))
        .thenAnswer((_) => Future.value('data:${jsonEncode({
                  'enrollmentId': '123',
                  'status': 'pending'
                })}'));

    AtEnrollmentResponse atEnrollmentResponse =
        await atEnrollmentServiceImpl.enroll(
      atsign: alice,
      rootDomain: AtRootDomain.atsignDomain,
      appName: 'wavi',
      deviceName: 'pixel',
      otp: testOtp(),
      namespaces: [
        NamespacePermission(namespace: 'wavi', read: true, write: true)
      ],
    );

    expect(atEnrollmentResponse.enrollmentId, '123');
    expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
    // submit mints the APKAM keypair and symmetric key locally; they are not
    // yet persistable, so they ride back on the response.
    final pending = atEnrollmentResponse as PendingEnrollment;
    expect(pending.atKeys.apkamPrivateKey, isNotNull);
    expect(pending.atKeys.apkamSymmetricKey, isNotNull);
    expect(pending.atKeys.defaultSelfEncryptionKey, isNull,
        reason: 'the atServer only releases this at approval');
  });

  group('approve / deny', () {
    test('A test to verify the approve enrollment', () async {
      String encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
      String encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
      String selfEncryptionKey = aesKeyMap[atSign]!;

      // What the atServer relays to the approver is whatever the *enrollee's*
      // conveyance wrapped — raw symmetric-key bytes under RSA, not the base64
      // text of them. Produce it the same way rather than by hand, so the
      // fixture cannot drift from what enroll() actually sends.
      final conveyed = await const RsaKeyConveyance()
          .wrap(AtBytes.fromString(encryptionPublicKey));

      // The approver's own keys, reached the way everything else reaches keys:
      // through an AtKeysIo.
      AtKeys approverKeys = AtKeys(atsign: alice)
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionPrivateKey)
        ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey);
      final approverIo = EphemeralAtKeysIo();
      await approverIo.write(alice, approverKeys);

      AtLookUp mockAtLookUp = MockAtLookUp();
      AtEnrollment atEnrollmentBase = AtEnrollmentImpl(mockAtLookUp);

      // approve goes out as a VerbBuilder, unlike deny/revoke which build their
      // own command string.
      when(() => mockAtLookUp.executeVerb(any(that: isA<EnrollVerbBuilder>())))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'status': 'approved',
                    'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
                  })}'));

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.approve(
        alice,
        approverIo,
        '4be2d358-074d-4e3b-99f3-64c4da01532f',
        AtBytes(conveyed.cipher),
      );

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.approved);
    });

    test('approve throws when the approver has no keys to re-encrypt with',
        () async {
      final emptyIo = EphemeralAtKeysIo();
      await emptyIo.write(alice, AtKeys(atsign: alice));

      AtLookUp mockAtLookUp = MockAtLookUp();
      AtEnrollment atEnrollmentBase = AtEnrollmentImpl(mockAtLookUp);

      expect(
          () async => await atEnrollmentBase.approve(
              alice, emptyIo, 'enroll-1', AtBytes.fromString('c2VjcmV0')),
          throwsA(isA<AtAuthenticationException>()));
    });

    test('A test to verify the deny enrollment', () async {
      AtLookUp mockAtLookUp = MockAtLookUp();
      AtEnrollment atEnrollmentBase = AtEnrollmentImpl(mockAtLookUp);

      when(() => mockAtLookUp
              .executeCommand(any(that: startsWith('enroll:deny')), auth: true))
          .thenAnswer((_) => Future.value('data:${jsonEncode({
                    'status': 'denied',
                    'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
                  })}'));

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.deny('4be2d358-074d-4e3b-99f3-64c4da01532f');

      expect(atEnrollmentResponse.enrollmentId,
          '4be2d358-074d-4e3b-99f3-64c4da01532f');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.denied);
    });
  });

  group('waitForApproval', () {
    late AtLookUp requesterLookUp;
    late AtLookUp enrollmentLookUp;
    late List<AtKeys?> factoryKeys;
    late EphemeralAtKeysIo keysIo;
    late PendingEnrollment pending;
    final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
    final encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    final selfEncryptionKey = aesKeyMap[atSign]!;

    setUp(() async {
      requesterLookUp = MockAtLookUp();
      enrollmentLookUp = MockAtLookUp();
      factoryKeys = [];
      keysIo = EphemeralAtKeysIo();

      pending = PendingEnrollment('enroll-9', EnrollmentStatus.pending,
          atKeys: AtKeys(atsign: alice)
            ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
            ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey));

      when(() => enrollmentLookUp.pkamAuthenticate(enrollmentId: 'enroll-9'))
          .thenAnswer((_) async => true);
      when(() => requesterLookUp.executeCommand(any(
          that:
              contains('default_enc_private_key')))).thenAnswer((_) async =>
          'data:${jsonEncode(await serverHeldKey(encryptionPrivateKey, apkamSymmetricKey))}');
      when(() => requesterLookUp.executeCommand(
          any(
              that: contains('default_self_enc_key')))).thenAnswer((_) async =>
          'data:${jsonEncode(await serverHeldKey(selfEncryptionKey, apkamSymmetricKey))}');
    });

    AtEnrollmentImpl buildEnrollment() => AtEnrollmentImpl(
          requesterLookUp,
          atLookUpFactory: (_, __, keys, {enrollmentId}) {
            factoryKeys.add(keys);
            return enrollmentLookUp;
          },
        );

    test('PKAMs on its own connection, built from the pending APKAM keys',
        () async {
      await buildEnrollment().waitForApproval(
          alice, AtRootDomain.atsignDomain, keysIo, pending,
          logProgress: false);

      // The requester's connection was built before the APKAM keypair existed,
      // so it cannot sign for this enrollment. A second one must be built from
      // the pending keys.
      expect(factoryKeys, hasLength(1));
      expect(factoryKeys.single, same(pending.atKeys));
      verify(() => enrollmentLookUp.pkamAuthenticate(enrollmentId: 'enroll-9'))
          .called(1);
      verifyNever(() => requesterLookUp.pkamAuthenticate(
          enrollmentId: any(named: 'enrollmentId')));
    });

    test('completes the keyset from the atServer and persists it', () async {
      await buildEnrollment().waitForApproval(
          alice, AtRootDomain.atsignDomain, keysIo, pending,
          logProgress: false);

      // Approval is what releases these two; before it the keyset could not be
      // persisted at all.
      expect(pending.atKeys.defaultSelfEncryptionKey.toString(),
          selfEncryptionKey);
      expect(pending.atKeys.defaultEncryptionPrivateKey.toString(),
          encryptionPrivateKey);

      final persisted = await keysIo.read(alice);
      expect(persisted.defaultSelfEncryptionKey.toString(), selfEncryptionKey);
    });

    test('throws when the pending keys carry no APKAM private key', () async {
      final keyless = PendingEnrollment('enroll-9', EnrollmentStatus.pending,
          atKeys: AtKeys(atsign: alice));

      expect(
          () async => await buildEnrollment().waitForApproval(
              alice, AtRootDomain.atsignDomain, keysIo, keyless,
              logProgress: false),
          throwsA(isA<AtAuthenticationException>()));
    });
  });

  group('the enrolled key follows the signing scheme', () {
    late AtLookUp requesterLookUp;
    late AtLookUp enrollmentLookUp;
    late List<String> enrollCommands;
    late List<AtKeys?> factoryKeys;

    setUp(() {
      requesterLookUp = MockAtLookUp();
      enrollmentLookUp = MockAtLookUp();
      enrollCommands = [];
      factoryKeys = [];

      when(() =>
              requesterLookUp.executeCommand(any(that: startsWith('enroll:'))))
          .thenAnswer((invocation) async {
        enrollCommands.add(invocation.positionalArguments.first as String);
        return 'data:${jsonEncode({
              'enrollmentId': 'enroll-9',
              'status': 'pending'
            })}';
      });
      when(() => enrollmentLookUp.pkamAuthenticate(enrollmentId: 'enroll-9'))
          .thenAnswer((_) async => true);
    });

    /// The public key `enroll` looks up on the atServer to convey the APKAM
    /// symmetric key to. Which one depends on the scheme's conveyance, not on
    /// its signing algorithm: RSA wraps, X-Wing encapsulates.
    void stubPublishedPublicKey(String base64PublicKey) {
      when(() => requesterLookUp
              .executeVerb(any(that: LookUpVerbBuilderMatcher())))
          .thenAnswer((_) async => 'data:$base64PublicKey');
    }

    AtEnrollmentImpl buildEnrollment(ApkamSigningScheme signing) =>
        AtEnrollmentImpl(
          requesterLookUp,
          signing: signing,
          atLookUpFactory: (_, __, keys, {enrollmentId}) {
            factoryKeys.add(keys);
            return enrollmentLookUp;
          },
        );

    Future<AtEnrollmentResponse> submit(AtEnrollmentImpl enrollment) =>
        enrollment.enroll(
          atsign: alice,
          rootDomain: AtRootDomain.atsignDomain,
          appName: 'wavi',
          deviceName: 'pixel',
          otp: testOtp(),
          namespaces: [
            NamespacePermission(namespace: 'wavi', read: true, write: true)
          ],
        );

    /// The enroll verb's params, as the atServer would parse them.
    Map<String, dynamic> enrollParams() => jsonDecode(
        enrollCommands.single.substring(enrollCommands.single.indexOf('{')));

    test('stamps the scheme on the enroll verb', () async {
      for (final signing in ApkamSigningScheme.values) {
        enrollCommands.clear();
        stubPublishedPublicKey(signing == ApkamSigningScheme.legacy
            ? encryptionPublicKeyMap[atSign]!
            : base64Encode((await XWingPureDartAlgo.instance.generateKeyPair())
                .publicKey));

        await submit(buildEnrollment(signing));

        expect(enrollParams()['signingAlgo'], signing.signingAlgo,
            reason: 'the atServer is told which algorithm to verify with');
      }
    });

    test('a postQuantum enrollment mints ML-DSA and no legacy keypair',
        () async {
      stubPublishedPublicKey(base64Encode(
          (await XWingPureDartAlgo.instance.generateKeyPair()).publicKey));

      final response =
          await submit(buildEnrollment(ApkamSigningScheme.postQuantum))
              as PendingEnrollment;

      expect(
          ApkamSigningScheme.postQuantum
              .requireApkamPublicKey(response.atKeys)
              .bytes,
          isNotEmpty);
      expect(response.atKeys.apkamPublicKey, isNull,
          reason: 'a PQ enrollment mints no legacy keypair');
    });

    test(
        'enrolls the APKAM public key it minted, not the atsign\'s published '
        'key', () async {
      // Two different keys are in play and they are easy to confuse: the
      // atsign's published key is the *recipient* the symmetric key is conveyed
      // to, while the enroll verb's apkamPublicKey is the key the atServer will
      // verify this enrollment's PKAM signatures with. Sending the former would
      // record a key the enrollment can never sign with.
      final published = encryptionPublicKeyMap[atSign]!;
      stubPublishedPublicKey(published);

      final response = await submit(buildEnrollment(ApkamSigningScheme.legacy))
          as PendingEnrollment;

      expect(enrollParams()['apkamPublicKey'],
          response.atKeys.apkamPublicKey.toString());
      expect(enrollParams()['apkamPublicKey'], isNot(published));
      // Legacy still keeps the published key: under this scheme it really is
      // the atsign's default encryption public key.
      expect(response.atKeys.defaultEncryptionPublicKey.toString(), published);
    });

    test(
        'a postQuantum enrollment keeps the X-Wing keypackage out of the '
        'legacy encryption field', () async {
      // Under postQuantum the published key is an X-Wing keypackage, not an RSA
      // encryption key, so it has no business in defaultEncryptionPublicKey.
      stubPublishedPublicKey(base64Encode(
          (await XWingPureDartAlgo.instance.generateKeyPair()).publicKey));

      final response =
          await submit(buildEnrollment(ApkamSigningScheme.postQuantum))
              as PendingEnrollment;

      expect(response.atKeys.defaultEncryptionPublicKey, isNull);
      expect(
          enrollParams()['apkamPublicKey'],
          ApkamSigningScheme.postQuantum
              .requireApkamPublicKey(response.atKeys)
              .toString());
    });

    test('a postQuantum enrollment completes end to end', () async {
      // enroll mints ML-DSA under KeyIds.apkamPQ and waitForApproval builds its
      // connection from that same material — the two agreeing is what makes a
      // PQ enrollment completable at all.
      stubPublishedPublicKey(base64Encode(
          (await XWingPureDartAlgo.instance.generateKeyPair()).publicKey));

      final enrollment = buildEnrollment(ApkamSigningScheme.postQuantum);
      final pending = await submit(enrollment) as PendingEnrollment;

      final symmetricKey = pending.atKeys.apkamSymmetricKey.toString();
      when(() => requesterLookUp.executeCommand(any(
          that:
              contains('default_enc_private_key')))).thenAnswer((_) async =>
          'data:${jsonEncode(await serverHeldKey(encryptionPrivateKeyMap[atSign]!, symmetricKey))}');
      when(() => requesterLookUp.executeCommand(
          any(
              that: contains('default_self_enc_key')))).thenAnswer((_) async =>
          'data:${jsonEncode(await serverHeldKey(aesKeyMap[atSign]!, symmetricKey))}');

      await enrollment.waitForApproval(
          alice, AtRootDomain.atsignDomain, EphemeralAtKeysIo(), pending,
          logProgress: false);

      // The keys handed to the factory were the ML-DSA ones, not a legacy
      // keypair that was never minted.
      expect(factoryKeys, hasLength(1));
      expect(
          ApkamSigningScheme.postQuantum
              .requireApkamPrivateKey(factoryKeys.single!)
              .bytes,
          isNotEmpty);
      expect(factoryKeys.single!.apkamPrivateKey, isNull);
    });

    test('waitForApproval rejects a keyset minted for the other scheme',
        () async {
      stubPublishedPublicKey(encryptionPublicKeyMap[atSign]!);
      final pending = await submit(buildEnrollment(ApkamSigningScheme.legacy))
          as PendingEnrollment;

      // No injected factory here: the rejection is the default factory's, and
      // injecting one would bypass exactly the check under test.
      final pqEnrollment = AtEnrollmentImpl(requesterLookUp,
          signing: ApkamSigningScheme.postQuantum);

      expect(
          () async => await pqEnrollment.waitForApproval(
              alice, AtRootDomain.atsignDomain, EphemeralAtKeysIo(), pending,
              logProgress: false),
          throwsA(isA<AtAuthenticationException>()));
    });
  });

  group('AtEnrollmentResponse toJson / fromJson', () {
    test('toJson includes enrollmentId and enrollStatus only', () {
      final response =
          AtEnrollmentResponse('enroll-123', EnrollmentStatus.approved);

      expect(response.toJson(),
          equals({'enrollmentId': 'enroll-123', 'enrollStatus': 'approved'}));
    });

    test('toJson excludes the pending keys', () {
      // Key material must never cross a process boundary in a response — it
      // stays in memory on PendingEnrollment until an AtKeysIo persists it.
      final pending = PendingEnrollment(
        'enroll-123',
        EnrollmentStatus.pending,
        atKeys: AtKeys(atsign: '@alice'.toAtsign()),
      );

      expect(pending.toJson().containsKey('keys'), isFalse);
      expect(pending.toJson().containsKey('atKeys'), isFalse);
    });

    test('fromJson restores enrollmentId and enrollStatus', () {
      final response = AtEnrollmentResponse.fromJson(
          {'enrollmentId': 'enroll-456', 'enrollStatus': 'denied'});

      expect(response.enrollmentId, 'enroll-456');
      expect(response.enrollStatus, EnrollmentStatus.denied);
    });

    test('fromJson throws when enrollStatus is unknown', () {
      expect(
        () => AtEnrollmentResponse.fromJson(
            {'enrollmentId': 'enroll-456', 'enrollStatus': 'invalidStatus'}),
        throwsA(isA<StateError>()),
      );
    });

    test('fromJson throws when enrollmentId is missing', () {
      expect(
        () => AtEnrollmentResponse.fromJson({'enrollStatus': 'approved'}),
        throwsA(anything),
      );
    });
  });

  group('firstEnrollment', () {
    late AtLookUp cramLookUp;
    late List<String> enrollCommands;

    setUp(() {
      cramLookUp = MockAtLookUp();
      enrollCommands = [];
      when(() => cramLookUp.executeCommand(any(that: startsWith('enroll:'))))
          .thenAnswer((invocation) async {
        enrollCommands.add(invocation.positionalArguments.first as String);
        return 'data:${jsonEncode({
              'enrollmentId': 'enroll-1',
              'status': 'approved'
            })}';
      });
    });

    Map<String, dynamic> enrollParams() => jsonDecode(
        enrollCommands.single.substring(enrollCommands.single.indexOf('{')));

    test('names the activation enrollment by default', () async {
      // The atServer reserves these two names for the enrollment an activation
      // creates; they used to be constants on the deleted FirstEnrollmentRequest
      // and are now the parameter defaults.
      final response =
          await AtEnrollmentImpl(cramLookUp).firstEnrollment('cHVi');

      expect(enrollParams()['appName'], 'firstApp');
      expect(enrollParams()['deviceName'], 'firstDevice');
      expect(response.enrollmentId, 'enroll-1');
      expect(response.enrollStatus, EnrollmentStatus.approved);
    });

    test('takes the caller\'s names and stamps the signing scheme', () async {
      await AtEnrollmentImpl(cramLookUp,
              signing: ApkamSigningScheme.postQuantum)
          .firstEnrollment('cHVi', appName: 'wavi', deviceName: 'pixel');

      expect(enrollParams()['appName'], 'wavi');
      expect(enrollParams()['deviceName'], 'pixel');
      expect(enrollParams()['apkamPublicKey'], 'cHVi');
      expect(enrollParams()['signingAlgo'],
          ApkamSigningScheme.postQuantum.signingAlgo);
    });
  });
}

class LookUpVerbBuilderMatcher extends Matcher {
  @override
  Description describe(Description description) {
    return description;
  }

  @override
  bool matches(item, Map matchState) {
    if (item is LookupVerbBuilder) {
      return true;
    }
    return false;
  }
}
