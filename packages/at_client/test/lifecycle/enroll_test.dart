import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `Atsign.enroll`, `PendingEnrollment` and `resumeEnrollment`: the key store
/// named at submission is the resume record, approval completes it, and a
/// denial empties it.
///
/// The atServer is a mocked lookup that answers by verb, and the approver is
/// modelled faithfully: it unwraps the symmetric key the request RSA-wrapped
/// to the atSign's encryption public key and seals the atSign's secrets under
/// it, which is what the handshake then opens. Legacy key exchange only; the
/// pq mode's approver needs a key-package encapsulation the live packs cover.
void main() {
  const atSign = '@alice🛠';
  const enrollmentId = 'e-1';
  final encryptionPublicKey = demo.encryptionPublicKeyMap[atSign]!;
  final encryptionPrivateKey = demo.encryptionPrivateKeyMap[atSign]!;
  final selfEncryptionKey = demo.aesKeyMap[atSign]!;
  late Directory dir;

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('enroll_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<AtClientPreference> preference() async => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = await refusedPort()
    ..hiveStoragePath = dir.path
    ..namespace = 'lifecycle';

  /// The atServer and the manager's approving client in one double.
  ///
  /// [decide] answers each PKAM attempt after submission: `true` approves,
  /// and an exception is the atServer's refusal, `AT0026` for not-yet-decided
  /// and `AT0025` for denied.
  MockAtLookupImpl atServer({required Future<bool> Function(int attempt) decide}) {
    final lookUp = MockAtLookupImpl();
    String? wrappedSymmetricKey;
    var attempts = 0;

    /// What a real approver does with the request: unwrap the symmetric key
    /// with the atSign's encryption private key, and seal a secret under it.
    Future<Map<String, String>> sealed(String secret) async {
      final symmetricKey = utf8.decode((RsaEncryptionAlgo()
            ..atPrivateKey = AtPrivateKey.fromString(encryptionPrivateKey))
          .decrypt(base64Decode(wrappedSymmetricKey!)));
      final iv = InitialisationVector.random(16);
      final bytes = await AESEncryptionAlgo(AESKey(symmetricKey))
          .encrypt(Uint8List.fromList(utf8.encode(secret)), iv: iv);
      return {
        'value': base64Encode(bytes),
        'iv': base64Encode(iv.ivBytes),
      };
    }

    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((invocation) async {
      final command = invocation.positionalArguments.first as String;
      if (command.startsWith('enroll:')) {
        final json = jsonDecode(
            command.substring(command.indexOf('{'), command.lastIndexOf('}') + 1));
        wrappedSymmetricKey = json['encryptedAPKAMSymmetricKey'] as String;
        return 'data:${jsonEncode({
              'enrollmentId': enrollmentId,
              'status': 'pending'
            })}';
      }
      if (command.startsWith('keys:get:keyName:$enrollmentId.default_enc_private_key')) {
        return 'data:${jsonEncode(await sealed(encryptionPrivateKey))}';
      }
      if (command.startsWith('keys:get:keyName:$enrollmentId.default_self_enc_key')) {
        return 'data:${jsonEncode(await sealed(selfEncryptionKey))}';
      }
      throw StateError('the mocked atServer has no answer for: $command');
    });
    when(() => lookUp.executeVerb(any())).thenAnswer((invocation) async {
      final builder = invocation.positionalArguments.first;
      if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
        return 'data:$encryptionPublicKey';
      }
      throw StateError('the mocked atServer has no answer for: '
          '${(builder as VerbBuilder).buildCommand()}');
    });
    when(() => lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) => decide(++attempts));
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  Future<PendingEnrollment> submit(InMemoryAtKeysIo store, MockAtLookupImpl server,
          {String device = 'phone'}) async =>
      Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: device,
          namespaces: {'wavi': 'rw'},
          keys: store,
          preference: await preference(),
          atLookUp: server);

  test('submission files the minted keys as pending in the store named', () async {
    final store = InMemoryAtKeysIo();
    final pending = await submit(store, atServer(decide: (_) async => true));

    expect(pending.enrollmentId, enrollmentId);
    expect(pending.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);
    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, [enrollmentId]);
    expect(stored.holdsAuthenticationMaterial, isFalse,
        reason: 'a keypair the atServer has not accepted authenticates as '
            'nobody, and no published reader finds a flat APKAM keypair');
    final snapshot = stored.enrollmentInfo(enrollmentId)!;
    expect((snapshot.appName, snapshot.deviceName), ('wavi', 'phone'));
    expect(snapshot.namespaces, {'wavi': 'rw'});
    // ignore: deprecated_member_use
    expect(stored.apkamSymmetricKey, isNotNull,
        reason: 'a legacy request carries its own symmetric key, which the '
            'handshake needs after approval');
  });

  test('open refuses a store that holds only a pending enrollment', () async {
    final store = InMemoryAtKeysIo();
    await submit(store, atServer(decide: (_) async => true));

    await expectLater(
        () async => Atsign(atSign).open(keys: store, preference: await preference()),
        throwsA(isA<AtEnrollmentPendingException>()
            .having((e) => e.pendingEnrollmentIds, 'pending', [enrollmentId])));
  });

  test('resumeEnrollment finds the request by app and device, and only that',
      () async {
    final store = InMemoryAtKeysIo();
    await submit(store, atServer(decide: (_) async => true));
    final pref = await preference();

    final resumed = await Atsign(atSign).resumeEnrollment(
        app: 'wavi', device: 'phone', keys: store, preference: pref);
    expect(resumed?.enrollmentId, enrollmentId);
    expect(resumed?.signingAlgo, SigningAlgoType.rsa2048);
    expect(resumed?.keyExchangeMode, EnrollmentKeyExchangeMode.legacy);

    expect(
        await Atsign(atSign).resumeEnrollment(
            app: 'wavi', device: 'tablet', keys: store, preference: pref),
        isNull,
        reason: 'another device\'s request is not this one');
    expect(
        await Atsign(atSign).resumeEnrollment(
            app: 'wavi', device: 'phone', keys: InMemoryAtKeysIo(), preference: pref),
        isNull,
        reason: 'and a store holding nothing resumes nothing');
  });

  test('a second request for the same app and device is refused in favour of '
      'resuming', () async {
    final store = InMemoryAtKeysIo();
    final server = atServer(decide: (_) async => true);
    await submit(store, server);

    await expectLater(
        () => submit(store, server),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', contains('resumeEnrollment'))));
  });

  test('approval completes the store, moves the keys to active, and opens a '
      'client', () async {
    final store = InMemoryAtKeysIo();
    // Not yet decided on the first poll, approved on the second: the wait is
    // exercised, not skipped.
    final server = atServer(
        decide: (attempt) async => attempt == 1
            ? throw UnAuthenticatedException(
                'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed')
            : true);
    final pending = await submit(store, server);

    final client = await pending.client(await preference(),
        retryInterval: const Duration(milliseconds: 10));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty);
    expect(stored.authenticatableEnrollmentIds, [enrollmentId]);
    expect(stored.enrollmentToAuthenticateAs(), enrollmentId);
    // ignore: deprecated_member_use
    expect(stored.defaultEncryptionPrivateKey?.toString(), encryptionPrivateKey,
        reason: 'the secret the approver sealed, opened by the handshake');
    // ignore: deprecated_member_use
    expect(stored.defaultSelfEncryptionKey?.toString(), selfEncryptionKey);
    // ignore: deprecated_member_use
    expect(stored.apkamPrivateKey, isNotNull,
        reason: 'an rsa2048 keypair is copied into the flat fields too, so the '
            'completed keyfile reads as a legacy one would');
    expect(stored.enrollmentInfo(enrollmentId)?.namespaces, {'wavi': 'rw'},
        reason: 'the snapshot filed at submission survives the completion');

    expect(client.enrollmentId, enrollmentId);
    expect(client.connection.current.isOnline, isTrue);
    await client.stop();
  });

  test('a denial removes the pending keys, throws, and leaves the store ready '
      'for the next request', () async {
    final store = InMemoryAtKeysIo();
    final denying = atServer(
        decide: (_) async => throw UnAuthenticatedException(
            'Failed connecting to $atSign. error:AT0025:Apkam Auth Denied'));
    final pending = await submit(store, denying);

    await expectLater(
        () async => pending.client(await preference(),
            retryInterval: const Duration(milliseconds: 10)),
        throwsA(isA<AtEnrollmentException>()
            .having((e) => e.message, 'message', contains('denied'))));

    final stored = await store.read(atSign);
    expect(stored.pendingEnrollmentIds, isEmpty);
    expect(stored.enrollmentIds, isEmpty,
        reason: 'the slot and its snapshot are gone, not retired');
    expect(stored.holdsAuthenticationMaterial, isFalse);

    // The emptied store takes the next request, which mints new keys.
    final again = await submit(store, atServer(decide: (_) async => true));
    expect((await store.read(atSign)).pendingEnrollmentIds, [again.enrollmentId]);
  });
}
