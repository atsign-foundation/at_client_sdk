import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/holds_none_of.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockAtEnrollment extends Mock implements AtEnrollment {}

class MockPkamAuthenticator extends Mock implements PkamAuthenticator {}

class FakeVerbBuilder extends Fake implements VerbBuilder {}

class FakeAtLookUp extends Fake implements AtLookupImpl {}

class FakeEnrollmentRequest extends Fake implements EnrollmentRequest {}

class FakeSecondaryAddressFinder implements SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    return SecondaryAddress('abcd', 123);
  }
}

/// Activation with a CRAM secret, against an atKeys file it cannot read or a
/// path it cannot write.
///
/// Catalogue: features/at_auth/activation_unreadable_keyfile.feature
void main() {
  const atSign = '@alice';
  const cramSecret = 'cram-3e9b1f6c2a7d4058';
  const eacces = 13;
  final random = Random.secure();

  late Directory dir;
  late MockAtLookUp lookUp;
  late MockAtEnrollment enrollment;
  late MockPkamAuthenticator pkam;
  late AtAuthImpl atAuth;

  String randomBase64(int bytes) =>
      base64Encode(List.generate(bytes, (_) => random.nextInt(256)));

  setUpAll(() {
    registerFallbackValue(FakeVerbBuilder());
    registerFallbackValue(FakeEnrollmentRequest());
    registerFallbackValue(FakeAtLookUp());
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('activation_keyfile');
    lookUp = MockAtLookUp();
    enrollment = MockAtEnrollment();
    pkam = MockPkamAuthenticator();
    // NOTE: every step answers, so an activation that goes ahead runs to the
    // write.
    when(() => lookUp.secondaryAddressFinder)
        .thenReturn(FakeSecondaryAddressFinder());
    when(() => lookUp.executeCommand(any(that: startsWith('lookup:publickey')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => throw AtLookUpException('AT0015', 'key not found'));
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) async => true);
    when(() => lookUp.executeVerb(any())).thenAnswer((_) async => 'data:2');
    when(() => lookUp.dropConnection()).thenAnswer((_) async {});
    when(() => pkam.authenticate(any(), any())).thenAnswer((_) async => true);
    when(() => enrollment.submit(any(), lookUp)).thenAnswer(
        (_) async => AtEnrollmentResponse('abc123', EnrollmentStatus.approved));
    atAuth = AtAuthImpl(
        atLookUp: lookUp, pkamAuthenticator: pkam, atEnrollment: enrollment);
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', dir.path]);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<AtOnboardingResponse> activate(FileAtKeysIo keys) => atAuth.onboard(
      AtOnboardingRequest(atSign,
          signingAlgoType: SigningAlgoType.rsa2048, atKeysIo: keys),
      cramSecret);

  void expectNothingSent() {
    verifyZeroInteractions(lookUp);
    verifyZeroInteractions(enrollment);
    verifyZeroInteractions(pkam);
  }

  /// Writes a keyfile for [atSign] at [path] and returns its private
  /// material.
  Future<List<String>> writeKeyfile(String path) async {
    final privates = [randomBase64(64), randomBase64(64), randomBase64(32)];
    await FileAtKeysIo(filePath: (_) => path).write(
        atSign,
        AtKeys.legacy(
          apkamPublicKey: randomBase64(64),
          apkamPrivateKey: privates[0],
          apkamSymmetricKey: randomBase64(32),
          encryptionPublicKey: randomBase64(64),
          encryptionPrivateKey: privates[1],
          selfEncryptionKey: privates[2],
        ));
    return privates;
  }

  final runningAsRoot =
      (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
  final Object skipModes = Platform.isWindows
      ? 'needs POSIX file modes'
      : runningAsRoot
          ? 'root reads and writes whatever the mode says'
          : false;

  group(
      'An existing keyfile activation cannot read is refused before anything '
      'is sent', () {
    late String path;

    setUp(() => path = '${dir.path}/${atSign}_key.atKeys');

    test('a keyfile this process cannot open', () async {
      final privates = await writeKeyfile(path);
      expect(Process.runSync('chmod', ['000', path]).exitCode, 0);

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<FileSystemException>()
              .having((e) => e.path, 'path', path)
              .having((e) => e.osError?.errorCode, 'osError.errorCode', eacces)
              .having((e) => '$e', 'text', contains(path))
              .having((e) => e, 'key material', holdsNoneOf(privates[0]))));
      expectNothingSent();
    }, skip: skipModes);

    test('text that is not JSON', () async {
      const text = 'plain text, 5e1c7a, not a document';
      await File(path).writeAsString(text);

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<AtKeysFormatException>()
              .having((e) => e.message, 'message',
                  allOf(contains(path), contains('not valid JSON')))
              .having((e) => e, 'file contents', holdsNoneOf(text))));
      expectNothingSent();
    });
  });

  group('An absent keyfile still activates', () {
    Future<void> activatesAt(String path) async {
      final response = await activate(FileAtKeysIo(filePath: (_) => path));

      expect(response.isSuccessful, isTrue);
      expect(response.enrollmentId, 'abc123');
      final written = await FileAtKeysIo(filePath: (_) => path).read(atSign);
      expect(written.enrollmentId, 'abc123',
          reason: 'the keys the activation minted are in the keyfile');
      expect(File(path).parent.listSync().map((e) => e.path), [path],
          reason: 'the keyfile is all the activation leaves in its directory');
      // NOTE: the control for expectNothingSent; the same double records the
      // CRAM exchange.
      verify(() => lookUp.pkamAuthenticate()).called(1);
    }

    test('in a directory that exists', () async {
      await activatesAt('${dir.path}/${atSign}_key.atKeys');
    });

    test('in a directory not yet created', () async {
      await activatesAt('${dir.path}/.atsign/keys/${atSign}_key.atKeys');
    });
  });
}
