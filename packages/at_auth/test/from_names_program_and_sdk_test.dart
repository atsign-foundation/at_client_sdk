// The keys an enrollee holds before its handshake are set through their flat
// fields, as `submit` leaves them.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/fake_cram_at_server.dart';

class _MockLookUp extends Mock implements AtLookupImpl {}

class _MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class _MockEnrollment extends Mock implements AtEnrollment {}

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

class _FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class _FakeLookUp extends Fake implements AtLookupImpl {}

class _FixedAddress implements SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}

/// Records every command an authenticator sends, answering each with an empty
/// response so the authenticator stops after `from:`.
class _RecordingExecutor implements AtCommandExecutor {
  final List<String> sent = [];

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    sent.add(command);
    return '';
  }
}

/// Catalogue: features/at_client/from_names_program_and_sdk.feature
void main() {
  final pubspecVersion = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(File('pubspec.yaml').readAsStringSync())!
      .group(1)!;
  const callerConfig = {
    'appName': 'acme_chat',
    'appVersion': '2.3.1',
    'sdkName': 'atsign.dart.at_client',
    'sdkVersion': '4.1.0',
  };

  setUpAll(() {
    registerFallbackValue(_FakeVerbBuilder());
    registerFallbackValue(_FakeEnrollmentRequest());
    registerFallbackValue(_FakeLookUp());
  });

  /// The clientConfig [fromCommand] carries for [atSign].
  Map<String, dynamic> configIn(String fromCommand, String atSign) {
    final prefix = 'from:$atSign:clientConfig:';
    expect(fromCommand, startsWith(prefix),
        reason: 'a from: without a clientConfig: $fromCommand');
    return jsonDecode(fromCommand.substring(prefix.length).trim())
        as Map<String, dynamic>;
  }

  /// The clientConfig each of [installed] sends, run as it would be.
  Future<List<Map<String, dynamic>>> configsSentBy(
      List<AtAuthenticator> installed, String atSign) async {
    final configs = <Map<String, dynamic>>[];
    for (final authenticator in installed) {
      final executor = _RecordingExecutor();
      await authenticator(executor);
      configs.add(configIn(executor.sent.first, atSign));
    }
    return configs;
  }

  test('a program using at_auth alone is named after at_auth', () async {
    final program =
        Uri.file(File('test/fixtures/acme_onboard.dart').absolute.path);
    final results = ReceivePort();
    final errors = ReceivePort();
    await Isolate.spawnUri(program, const [], results.sendPort,
        onError: errors.sendPort, packageConfig: await Isolate.packageConfig);
    final Object? result;
    try {
      result = await Future.any([
        results.first,
        errors.first.then((e) => throw StateError('acme_onboard failed: $e')),
      ]).timeout(const Duration(minutes: 3));
    } finally {
      results.close();
      errors.close();
    }
    final outcome = result as Map;
    expect(outcome['error'], isNull, reason: 'the activation threw');
    final froms = (outcome['froms'] as List).cast<String>();

    expect(froms, hasLength(2),
        reason: 'the control: the activation authenticated with CRAM, then '
            'with PKAM as its new enrollment');
    for (final from in froms) {
      final config = configIn(from, '@alice');
      expect(config['appName'], 'acme_onboard',
          reason: 'the program file is acme_onboard.dart');
      expect(config['appVersion'], 'unknown');
      expect(config['sdkName'], 'atsign.dart.at_auth');
      expect(config['sdkVersion'], pubspecVersion);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test(
      'Given a caller config, when activateAtSign authenticates with CRAM and '
      'then PKAM, then both from: commands carry it', () async {
    final atServer = FakeCramAtServer('@alice', cramReply: 'data:success');
    final lookUp = atServer.lookUp();
    addTearDown(lookUp.close);

    await activateAtSign(
        atSign: '@alice',
        cramSecret: 'the-one-time-secret',
        keys: InMemoryAtKeysIo(),
        signingAlgo: SigningAlgoType.rsa2048,
        atLookUp: lookUp,
        clientConfig: callerConfig);

    expect(atServer.froms, hasLength(2),
        reason: 'the control: CRAM, then PKAM as the new enrollment');
    for (final from in atServer.froms) {
      expect(configIn(from, '@alice'), callerConfig);
    }
  });

  test(
      'Given a caller config, when AtAuth.create onboards, then every '
      'authenticator it installs sends it', () async {
    const atSign = '@alice';
    final lookUp = _MockLookUp();
    when(() => lookUp.secondaryAddressFinder).thenReturn(_FixedAddress());
    when(() => lookUp.executeCommand(any(that: startsWith('lookup:publickey')),
            auth: any(named: 'auth')))
        .thenAnswer((_) async => throw AtLookUpException('AT0015', 'no key'));
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    final pkam = _MockPkamAuthenticator();
    when(() => pkam.authenticate(any(), any())).thenAnswer((_) async => true);
    final enrollment = _MockEnrollment();
    when(() => enrollment.submit(any(), lookUp)).thenAnswer(
        (_) async => AtEnrollmentResponse('e-1', EnrollmentStatus.approved));

    await AtAuth.create(
            atLookUp: lookUp,
            pkamAuthenticator: pkam,
            atEnrollmentBase: enrollment,
            clientConfig: callerConfig)
        .onboard(
            AtOnboardingRequest(atSign,
                signingAlgoType: SigningAlgoType.rsa2048)
              ..atKeysIo = InMemoryAtKeysIo(),
            'the-one-time-secret');

    final installed = verify(() => lookUp.authenticator = captureAny())
        .captured
        .whereType<AtAuthenticator>()
        .toList();
    expect(installed, hasLength(3),
        reason: 'the control: CRAM\'s, the new keys\', and the new keys\' '
            'again once the enrollment is named');
    for (final config in await configsSentBy(installed, atSign)) {
      expect(config, callerConfig);
    }
  });

  test(
      'Given a caller config, when AtEnrollment.create waits for approval, '
      'then the handshake\'s from: carries it', () async {
    const atSign = '@alice🛠';
    final apkamSymmetricKey = demo.apkamSymmetricKeyMap[atSign]!;
    final sealer = AESEncryptionAlgo(AESKey(apkamSymmetricKey));
    Future<String> sealed(String value) async => base64.encode(
        await sealer.encrypt(Uint8List.fromList(utf8.encode(value)),
            iv: InitialisationVector.legacy()));
    final lookUp = _MockLookUp();
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    final sealedPrivateKey =
        await sealed(demo.encryptionPrivateKeyMap[atSign]!);
    final sealedSelfKey = await sealed(demo.aesKeyMap[atSign]!);
    when(() =>
        lookUp.executeCommand(any(that: contains('default_enc_private_key')),
            auth: any(named: 'auth'))).thenAnswer(
        (_) async => 'data:${jsonEncode({'value': sealedPrivateKey})}');
    when(() =>
        lookUp.executeCommand(any(that: contains('default_self_enc_key')),
            auth: any(named: 'auth'))).thenAnswer(
        (_) async => 'data:${jsonEncode({'value': sealedSelfKey})}');
    final keys = AtKeys()
      ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
      ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
      ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey);

    await AtEnrollment.create(clientConfig: callerConfig).waitForApproval(
        AtEnrollmentResponse('123', EnrollmentStatus.pending,
            atSign: atSign,
            rootDomain: AtRootDomain.atsignDomain,
            atAuthKeys: keys),
        atLookup: lookUp);

    final installed = verify(() => lookUp.authenticator = captureAny())
        .captured
        .whereType<AtAuthenticator>()
        .toList();
    expect(installed, hasLength(1),
        reason: 'the control: the handshake installs one authenticator');
    expect((await configsSentBy(installed, atSign)).single, callerConfig);
  });
}
