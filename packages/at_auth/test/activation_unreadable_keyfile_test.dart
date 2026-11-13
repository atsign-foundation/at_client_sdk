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

/// A keys store with no path, whose read fails with [error].
class _UnreadableStore extends WrittenAtKeysIo {
  _UnreadableStore(this.error);

  final Object error;

  @override
  Future<AtKeys> read(String atsign) async => throw error;

  @override
  String describeSource(String atsign) => 'the test keys store';

  @override
  Future write(String atsign, AtKeys atKeys) async {}
}

/// Activation with a CRAM secret, against an atKeys file it cannot read or a
/// path it cannot write.
///
/// Catalogue: features/at_auth/activation_unreadable_keyfile.feature
void main() {
  const atSign = '@alice';
  const cramSecret = 'cram-3e9b1f6c2a7d4058';
  const passPhrase = 'passphrase-71c4e0a9';
  const otherPassPhrase = 'passphrase-d25f8b13';
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

  Future<AtOnboardingResponse> activate(WrittenAtKeysIo keys) => atAuth.onboard(
      AtOnboardingRequest(atSign,
          signingAlgoType: SigningAlgoType.rsa2048, atKeysIo: keys),
      cramSecret);

  void expectNothingSent() {
    verifyZeroInteractions(lookUp);
    verifyZeroInteractions(enrollment);
    verifyZeroInteractions(pkam);
  }

  /// Writes a keyfile for [atSign] at [path], passphrase-protected when
  /// [passPhrase] is given, and returns its private material.
  Future<List<String>> writeKeyfile(String path, {String? passPhrase}) async {
    final privates = [randomBase64(64), randomBase64(64), randomBase64(32)];
    await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase).write(
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
                  startsWith('the atKeys file $path is not valid JSON'))
              .having((e) => e, 'file contents', holdsNoneOf(text))));
      expectNothingSent();
    });

    test('a passphrase-protected keyfile read with the wrong passphrase',
        () async {
      final privates = await writeKeyfile(path, passPhrase: passPhrase);

      await expectLater(
          activate(
              FileAtKeysIo(filePath: (_) => path, passPhrase: otherPassPhrase)),
          throwsA(isA<AtDecryptionException>()
              .having(
                  (e) => e.message,
                  'message',
                  allOf(
                      contains(path), contains('passphrase may be incorrect')))
              .having(
                  (e) => e.message,
                  'passphrases',
                  allOf(isNot(contains(passPhrase)),
                      isNot(contains(otherPassPhrase))))
              .having(
                  (e) => e.message, 'CRAM secret', isNot(contains(cramSecret)))
              .having((e) => e, 'key material', holdsNoneOf(privates[1]))));
      expectNothingSent();
    });

    test('a passphrase-protected keyfile read with no passphrase', () async {
      final privates = await writeKeyfile(path, passPhrase: passPhrase);

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<AtDecryptionException>()
              .having((e) => e.message, 'message',
                  allOf(contains(path), contains('Pass Phrase is required')))
              .having((e) => e, 'key material', holdsNoneOf(privates[2]))));
      expectNothingSent();
    });
  });

  group(
      'A keyfile path activation cannot write is refused before anything is '
      'sent', () {
    late String locked;

    setUp(() {
      locked = '${dir.path}/locked';
      Directory(locked).createSync();
      expect(Process.runSync('chmod', ['500', locked]).exitCode, 0);
    });

    test('a directory this process cannot write', () async {
      final path = '$locked/${atSign}_key.atKeys';

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<FileSystemException>()
              .having((e) => e.path, 'path', path)
              .having((e) => e.osError?.errorCode, 'osError.errorCode', eacces)
              .having((e) => e.message, 'CRAM secret',
                  isNot(contains(cramSecret)))));
      expectNothingSent();
      expect(Directory(locked).listSync(), isEmpty,
          reason: 'the check leaves nothing in the directory it checked');
    }, skip: skipModes);

    test('a directory that does not exist and cannot be created', () async {
      final path = '$locked/keys/${atSign}_key.atKeys';

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<FileSystemException>()
              .having((e) => e.path, 'path', path)
              .having(
                  (e) => e.osError?.errorCode, 'osError.errorCode', eacces)));
      expectNothingSent();
    }, skip: skipModes);
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

  group('A refusal names a keys store that is not a file', () {
    const source = 'the test keys store';

    test('an AtKeysFormatException that does not name it is rebuilt naming it',
        () async {
      await expectLater(
          activate(_UnreadableStore(AtKeysFormatException.notJson('the entry',
              const FormatException('Unexpected character', null, 0)))),
          throwsA(isA<AtKeysFormatException>()
              .having((e) => e.message, 'message',
                  'the atKeys in $source is not valid JSON: Unexpected character (at character 1)')
              .having((e) => e.reason, 'reason', 'Unexpected character')
              .having((e) => e.position, 'position', 1)));
      expectNothingSent();
    });

    test('one that is not a JSON object still says so', () async {
      await expectLater(
          activate(
              _UnreadableStore(AtKeysFormatException.notAnObject('the entry'))),
          throwsA(isA<AtKeysFormatException>()
              .having((e) => e.message, 'message',
                  'the atKeys in $source is not a JSON object')
              .having((e) => e.position, 'position', isNull)));
      expectNothingSent();
    });

    test('a FormatException names it and holds none of its text', () async {
      final text = '{"aesPkamPrivateKey": "${randomBase64(32)}"';

      await expectLater(
          activate(_UnreadableStore(
              FormatException('Unexpected end of input', text, text.length))),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message',
                  '$source cannot be read: Unexpected end of input')
              .having((e) => e.source, 'source', isNull)
              .having((e) => e.offset, 'offset', text.length)
              .having((e) => e, 'text', holdsNoneOf(text))));
      expectNothingSent();
    });

    test('an AtException keeps its type and names it', () async {
      final error = AtKeysValidationException('Unsupported atKeys version: 2');

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(allOf(
              same(error),
              isA<AtKeysValidationException>().having(
                  (e) => e.message,
                  'message',
                  '$source cannot be read: Unsupported atKeys version: 2'))));
      expectNothingSent();
    });

    test('a message that already names it is left as it is', () async {
      final error =
          AtKeysValidationException('$source holds a version 2 document');

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(isA<AtKeysValidationException>().having((e) => e.message,
              'message', '$source holds a version 2 document')));
      expectNothingSent();
    });

    test('an error with no message to carry it is rethrown as it is', () async {
      final error = StateError('the store is closed');

      await expectLater(
          activate(_UnreadableStore(error)), throwsA(same(error)));
      expectNothingSent();
    });
  });

  group('describeSource', () {
    test('of a FileAtKeysIo is the keyfile path', () {
      expect(
          FileAtKeysIo(filePath: (a) => '/keys/${a}_key.atKeys')
              .describeSource(atSign),
          '/keys/${atSign}_key.atKeys');
    });

    test('of a store that does not say is the keys store', () {
      expect(InMemoryAtKeysIo().describeSource(atSign), 'the keys store');
    });
  });
}
