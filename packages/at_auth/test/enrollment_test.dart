import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:at_demo_data/at_demo_data.dart';

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

    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        atsign: alice,
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: [
          NamespacePermission(namespace: 'wavi', read: true, write: true)
        ]);

    AtEnrollmentResponse atEnrollmentResponse =
        await atEnrollmentServiceImpl.enroll(enrollmentRequest);

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

  group('A group of tests related EnrollmentRequestDecision', () {
    test('A test to verify the approve enrollment', () async {
      String encryptionPublicKey = encryptionPublicKeyMap[atSign]!;
      String encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
      String selfEncryptionKey = aesKeyMap[atSign]!;
      String apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;

      String encryptedAPKAMSymmetricKey =
          RSAPublicKey.fromString(encryptionPublicKey)
              .encrypt(apkamSymmetricKey);

      // The approver's own keys, reached the way everything else reaches keys:
      // through an AtKeysIo.
      AtKeys approverKeys = AtKeys(atsign: alice)
        ..defaultEncryptionPrivateKey = AtBytes.fromString(encryptionPrivateKey)
        ..defaultSelfEncryptionKey = AtBytes.fromString(selfEncryptionKey);
      final approverIo = EphemeralAtKeysIo();
      await approverIo.write(alice, approverKeys);

      AtLookUp mockAtLookUp = MockAtLookUp();
      AtEnrollment atEnrollmentBase = AtEnrollmentImpl(mockAtLookUp);

      when(() =>
          mockAtLookUp.executeCommand(any(that: startsWith('enroll:approve')),
              auth: true)).thenAnswer((_) => Future.value('data:${jsonEncode({
                'status': 'approved',
                'enrollmentId': '4be2d358-074d-4e3b-99f3-64c4da01532f'
              })}'));

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.approved(
        enrollmentId: '4be2d358-074d-4e3b-99f3-64c4da01532f',
        apkamSymmetricKey: AtBytes.fromString(encryptedAPKAMSymmetricKey),
        atsign: alice,
      );

      AtEnrollmentResponse atEnrollmentResponse = await atEnrollmentBase
          .approve(alice, approverIo, enrollmentRequestDecision);

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
              alice,
              emptyIo,
              EnrollmentRequestDecision.approved(
                enrollmentId: 'enroll-1',
                apkamSymmetricKey: AtBytes.fromString('c2VjcmV0'),
                atsign: alice,
              )),
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

      EnrollmentRequestDecision enrollmentRequestDecision =
          EnrollmentRequestDecision.denied(
              '4be2d358-074d-4e3b-99f3-64c4da01532f', alice);

      AtEnrollmentResponse atEnrollmentResponse =
          await atEnrollmentBase.deny(enrollmentRequestDecision);

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

    AtEnrollmentImpl buildEnrollment() => AtEnrollmentImpl(requesterLookUp)
      ..lookUpOverride = (keys, enrollmentId) {
        factoryKeys.add(keys);
        return enrollmentLookUp;
      };

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

  group('AtEnrollmentRequest', () {
    test('defaults rootDomain to the Atsign atDirectory', () {
      final request = AtEnrollmentRequest(
        atsign: alice,
        appName: 'wavi',
        deviceName: 'pixel',
        otp: 'A123FE',
        namespaces: [
          NamespacePermission(namespace: 'wavi', read: true, write: true)
        ],
      );

      expect(request.atsign, alice);
      expect(request.rootDomain, AtRootDomain.atsignDomain);
    });

    test('FirstEnrollmentRequest names the activation enrollment by default',
        () {
      final request =
          FirstEnrollmentRequest(atsign: alice, apkamPublicKey: 'cHVi');

      expect(request.appName, FirstEnrollmentRequest.defaultAppName);
      expect(request.deviceName, FirstEnrollmentRequest.defaultDeviceName);
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
