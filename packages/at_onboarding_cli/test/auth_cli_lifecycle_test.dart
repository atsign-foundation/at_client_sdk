import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// `at_activate onboard` and `at_activate enroll` below the argument parsing.
/// An activation writes the atSign's first keys to the keyfile named and
/// stops the client it opened; an enrollment files its keys in the keyfile
/// named, waits for approval and hands back a client on them, and a request
/// already in that keyfile is resumed rather than repeated.
///
/// The atServer is a mocked lookup answering by verb.
void main() {
  AtSignLogger.root_level = 'SHOUT';
  late Directory dir;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('auth_cli_lifecycle_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  Future<AtOnboardingPreference> preference() async =>
      AuthCliArgs.preferenceUnder(PqPosture.legacy)
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = await refusedPort()
        ..namespace = 'at_activate'
        ..storagePath = '${dir.path}/storage';

  Future<void> expectOwnerOnly(String path) async {
    if (Platform.isWindows) return;
    expect((await FileStat.stat(path)).mode & 0x1FF, 0x180,
        reason: 'the keyfile is readable by its owner alone');
  }

  group('activate', () {
    const atSign = '@newborn';
    const enrollmentId = 'first-1';
    const cramSecret = 'the-one-time-secret';

    /// An atServer as the registrar leaves it, unless [activated], in which
    /// case an activation has already published an encryption public key.
    ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
        {bool activated = false}) {
      final lookUp = MockAtLookupImpl();
      final sent = <String>[];
      when(() => lookUp.cramAuthenticate(any()))
          .thenAnswer((i) async => i.positionalArguments.first == cramSecret);
      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((i) async {
        final command = i.positionalArguments.first as String;
        sent.add(command);
        if (command.startsWith('lookup:publickey')) {
          return activated
              ? 'data:${demo.encryptionPublicKeyMap['@alice🛠']}'
              : 'data:null';
        }
        if (command.startsWith('enroll:')) {
          return 'data:${jsonEncode({
                'enrollmentId': enrollmentId,
                'status': 'approved'
              })}';
        }
        throw StateError('the mocked atServer has no answer for: $command');
      });
      when(() => lookUp.executeVerb(any())).thenAnswer((i) async {
        final builder = i.positionalArguments.first as VerbBuilder;
        sent.add(builder.buildCommand());
        if (builder is UpdateVerbBuilder || builder is DeleteVerbBuilder) {
          return 'data:1';
        }
        throw StateError('the mocked atServer has no answer for: '
            '${builder.buildCommand()}');
      });
      when(() =>
              lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
          .thenAnswer((_) async => true);
      when(() => lookUp.close()).thenAnswer((_) async {});
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      return (lookUp: lookUp, sent: sent);
    }

    test(
        'writes the first keys to the keyfile named, secures it, and stops '
        'the client', () async {
      final server = atServer();
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      final pref = (await preference())
        ..atKeysFilePath = keysPath
        ..cramSecret = cramSecret;

      await activate(atSign, pref, atLookUp: server.lookUp);

      final keys = await FileAtKeysIo(filePath: (_) => keysPath).read(atSign);
      expect(keys.enrollmentToAuthenticateAs(), enrollmentId);
      expect(keys.holdsAuthenticationMaterial, isTrue);
      expect(server.sent.where((c) => c.startsWith('enroll:')), hasLength(1));
      expect(
          server.sent.any((c) =>
              c.startsWith('delete:') && c.contains(AtConstants.atCramSecret)),
          isTrue,
          reason: 'the activation completed: the one-time secret is gone');
      expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
          reason: 'a command\'s client ends with the command');
      await expectOwnerOnly(keysPath);
    });

    test(
        'refuses an atSign whose atServer already publishes an encryption '
        'key, before minting anything', () async {
      final server = atServer(activated: true);
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      final pref = (await preference())
        ..atKeysFilePath = keysPath
        ..cramSecret = cramSecret;

      await expectLater(
          activate(atSign, pref, atLookUp: server.lookUp),
          throwsA(isA<AtActivateException>().having(
              (e) => e.message, 'message', contains('already activated'))));

      expect(server.sent.where((c) => c.startsWith('enroll:')), isEmpty);
      expect(File(keysPath).existsSync(), isFalse);
    });

    test('refuses to overwrite a keyfile that is already there', () async {
      final server = atServer();
      final keysPath = '${dir.path}/${atSign}_key.atKeys';
      File(keysPath).writeAsStringSync('{}');
      final pref = (await preference())
        ..atKeysFilePath = keysPath
        ..cramSecret = cramSecret;

      await expectLater(activate(atSign, pref, atLookUp: server.lookUp),
          throwsA(isA<AtKeysFileOverwriteException>()));

      expect(server.sent, isEmpty,
          reason: 'refused before the atServer was asked anything');
    });
  });

  group('enrolDevice', () {
    const atSign = '@alice🛠';
    const enrollmentId = 'e-1';
    final encryptionPublicKey = demo.encryptionPublicKeyMap[atSign]!;
    final encryptionPrivateKey = demo.encryptionPrivateKeyMap[atSign]!;
    final selfEncryptionKey = demo.aesKeyMap[atSign]!;

    /// The atServer and the approving client in one double. [decide] answers
    /// each PKAM attempt after submission: `true` approves, and an exception
    /// is the atServer's refusal. [wrapped] holds the symmetric key the
    /// request RSA-wrapped, shared between doubles so a wait resumed against
    /// a second one can be answered with secrets sealed under the same key.
    ({MockAtLookupImpl lookUp, List<String> sent}) atServer(
        {required Future<bool> Function(int attempt) decide,
        required List<String> wrapped}) {
      final lookUp = MockAtLookupImpl();
      final sent = <String>[];
      var attempts = 0;

      Future<Map<String, String>> sealed(String secret) async {
        final symmetricKey = utf8.decode((RsaEncryptionAlgo()
              ..atPrivateKey = AtPrivateKey.fromString(encryptionPrivateKey))
            .decrypt(base64Decode(wrapped.single)));
        final iv = InitialisationVector.random(16);
        final bytes = await AESEncryptionAlgo(AESKey(symmetricKey))
            .encrypt(Uint8List.fromList(utf8.encode(secret)), iv: iv);
        return {'value': base64Encode(bytes), 'iv': base64Encode(iv.ivBytes)};
      }

      when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
          .thenAnswer((i) async {
        final command = i.positionalArguments.first as String;
        sent.add(command);
        if (command.startsWith('enroll:')) {
          final json = jsonDecode(command.substring(
              command.indexOf('{'), command.lastIndexOf('}') + 1));
          wrapped
            ..clear()
            ..add(json['encryptedAPKAMSymmetricKey'] as String);
          return 'data:${jsonEncode({
                'enrollmentId': enrollmentId,
                'status': 'pending'
              })}';
        }
        if (command.startsWith(
            'keys:get:keyName:$enrollmentId.default_enc_private_key')) {
          return 'data:${jsonEncode(await sealed(encryptionPrivateKey))}';
        }
        if (command.startsWith(
            'keys:get:keyName:$enrollmentId.default_self_enc_key')) {
          return 'data:${jsonEncode(await sealed(selfEncryptionKey))}';
        }
        throw StateError('the mocked atServer has no answer for: $command');
      });
      when(() => lookUp.executeVerb(any())).thenAnswer((i) async {
        final builder = i.positionalArguments.first;
        if (builder is LookupVerbBuilder && builder.atKey.key == 'publicKey') {
          return 'data:$encryptionPublicKey';
        }
        throw StateError('the mocked atServer has no answer for: '
            '${(builder as VerbBuilder).buildCommand()}');
      });
      when(() =>
              lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
          .thenAnswer((_) => decide(++attempts));
      when(() => lookUp.close()).thenAnswer((_) async {});
      when(() => lookUp.isConnectionAvailable()).thenReturn(false);
      return (lookUp: lookUp, sent: sent);
    }

    Future<AtClient> enrol(AtOnboardingPreference pref, String keysPath,
            MockAtLookupImpl lookUp) =>
        enrolDevice(
            atSign: atSign,
            preference: pref,
            app: 'wavi',
            device: 'phone',
            otp: 'ABC123',
            namespaces: {'wavi': 'rw'},
            atKeysFilePath: keysPath,
            signingAlgo: SigningAlgoType.rsa2048,
            retryInterval: const Duration(milliseconds: 10),
            atLookUp: lookUp);

    test(
        'files the keys, waits for approval, secures the keyfile, and hands '
        'back an online client', () async {
      final server = atServer(decide: (_) async => true, wrapped: []);
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';

      final client = await enrol(await preference(), keysPath, server.lookUp);

      expect(client.enrollmentId, enrollmentId);
      expect(client.connection.current.isOnline, isTrue);
      final keys = await FileAtKeysIo(filePath: (_) => keysPath).read(atSign);
      expect(keys.enrollmentToAuthenticateAs(), enrollmentId);
      // ignore: deprecated_member_use
      expect(keys.defaultSelfEncryptionKey?.toString(), selfEncryptionKey,
          reason: 'the secret the approver sealed, opened by the handshake');
      await expectOwnerOnly(keysPath);
      await client.stop();
    });

    test('a request already in the keyfile is resumed, not repeated', () async {
      final wrapped = <String>[];
      final keysPath = '${dir.path}/${atSign}_wavi_key.atKeys';
      final pref = await preference();
      // Submitted earlier and never approved: the keyfile holds it pending.
      final first = atServer(
          decide: (_) async => throw UnAuthenticatedException(
              'Failed connecting to $atSign. error:AT0026:Apkam Auth Failed'),
          wrapped: wrapped);
      await Atsign(atSign).enroll(
          otp: 'ABC123',
          app: 'wavi',
          device: 'phone',
          namespaces: {'wavi': 'rw'},
          keys: FileAtKeysIo(filePath: (_) => keysPath),
          preference: pref,
          atLookUp: first.lookUp);
      expect(
          (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
              .pendingEnrollmentIds,
          [enrollmentId]);

      final second = atServer(decide: (_) async => true, wrapped: wrapped);
      final client = await enrol(pref, keysPath, second.lookUp);

      expect(second.sent.where((c) => c.startsWith('enroll:')), isEmpty,
          reason: 'the wait resumed from the keyfile; no second request');
      expect(client.enrollmentId, enrollmentId);
      expect(
          (await FileAtKeysIo(filePath: (_) => keysPath).read(atSign))
              .enrollmentToAuthenticateAs(),
          enrollmentId);
      await client.stop();
    });
  });
}
