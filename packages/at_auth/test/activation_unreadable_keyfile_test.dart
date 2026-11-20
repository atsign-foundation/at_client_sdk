import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/models/at_auth_requests.dart';
import 'package:at_auth/src/auth/models/at_auth_responses.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/keys/io/default_keyfile_path.dart';
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

/// A keys store with no path, named [source], whose read fails with
/// [error].
class _UnreadableStore extends WrittenAtKeysIo {
  _UnreadableStore(this.error, {this.source = 'the test keys store'});

  final Object error;
  final String source;

  @override
  Future<AtKeys> read(String atsign) async => throw error;

  @override
  String describeSource(String atsign) => source;

  @override
  Future write(String atsign, AtKeys atKeys) async {}
}

/// A keys store that cannot be written, holding nothing.
class _ReadOnlyStore extends GeneratedAtKeysIo {
  @override
  AtKeys read(String atsign) =>
      throw AtKeysSourceAbsentException('no keys for $atsign');

  @override
  AtKeys generateKeys(String publicKeyId) =>
      throw UnsupportedError('no keys are generated');
}

/// A real file whose delete is refused unless [deletable].
class _ProbeFile implements File {
  _ProbeFile(this._file, {required this.deletable});

  final File _file;
  final bool deletable;

  @override
  String get path => _file.path;

  @override
  Directory get parent => _file.parent;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await _file.create(recursive: recursive, exclusive: exclusive);
    return this;
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (!deletable) {
      throw FileSystemException(
          'Cannot delete file', path, const OSError('refused by the test', 1));
    }
    return _file.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A platform's refusal to read its keychain, as a plugin reports one.
class _PlatformRefusal implements Exception {
  @override
  String toString() =>
      'PlatformException(AuthError:UserCanceled, User canceled the '
      'operation., null, null)';
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
        atLookUp: lookUp,
        pkamAuthenticator: pkam,
        atEnrollment: enrollment,
        clientConfig: const {});
  });

  tearDown(() async {
    await Process.run('chmod', ['-R', 'u+rwx', dir.path]);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<AtOnboardingResponse> activate(WrittenAtKeysIo keys) => atAuth.onboard(
      AtOnboardingRequest(atSign,
          signingAlgoType: SigningAlgoType.rsa2048, atKeysIo: keys),
      cramSecret);

  /// [AtKeysUnusableException] with cause unreadable for [source], whose
  /// message is [message] and whose error matches [error].
  Matcher unreadable(String source, Object message, Matcher error) =>
      isA<AtKeysUnusableException>()
          .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
          .having((e) => e.atSign, 'atSign', atSign)
          .having((e) => e.source, 'source', source)
          .having((e) => e.message, 'message', message)
          .having((e) => e.error, 'error', error);

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
      await writeKeyfile(path);
      final text = File(path).readAsStringSync();
      expect(Process.runSync('chmod', ['000', path]).exitCode, 0);

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(allOf(
              unreadable(
                  path,
                  allOf(
                      startsWith('The keys for $atSign at $path could not be '
                          'read: '),
                      contains('Permission denied')),
                  isA<FileSystemException>()
                      .having((e) => e.path, 'path', path)
                      .having((e) => e.osError?.errorCode, 'osError.errorCode',
                          eacces)),
              holdsNoneOf(text, window: 16))));
      expectNothingSent();
    }, skip: skipModes);

    test('text that is not JSON', () async {
      const text = 'plain text, 5e1c7a, not a document';
      await File(path).writeAsString(text);

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(allOf(
              unreadable(
                  path,
                  'The keys for $atSign at $path could not be read: it is not '
                  'valid JSON: Unexpected character (at character 1).',
                  isA<AtKeysFormatException>()),
              holdsNoneOf(text))));
      expectNothingSent();
    });

    test('a passphrase-protected keyfile read with the wrong passphrase',
        () async {
      await writeKeyfile(path, passPhrase: passPhrase);
      final text = File(path).readAsStringSync();

      await expectLater(
          activate(
              FileAtKeysIo(filePath: (_) => path, passPhrase: otherPassPhrase)),
          throwsA(allOf(
              unreadable(
                  path,
                  allOf(
                      startsWith('The keys for $atSign at $path could not be '
                          'read: '),
                      contains('passphrase may be incorrect'),
                      isNot(contains(passPhrase)),
                      isNot(contains(otherPassPhrase)),
                      isNot(contains(cramSecret))),
                  isA<AtDecryptionException>()),
              holdsNoneOf(text, window: 16))));
      expectNothingSent();
    });

    test('a passphrase-protected keyfile read with no passphrase', () async {
      await writeKeyfile(path, passPhrase: passPhrase);
      final text = File(path).readAsStringSync();

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(allOf(
              unreadable(
                  path,
                  'The keys for $atSign at $path could not be read: Pass '
                  'Phrase is required for password protected atKeys file.',
                  isA<AtDecryptionException>()),
              holdsNoneOf(text, window: 16))));
      expectNothingSent();
    });
  });

  test('A keyfile path that cannot be resolved is unreadable keys', () async {
    await expectLater(
        activate(
            FileAtKeysIo(filePath: (a) => defaultAtKeysFilePathUnder(null, a))),
        throwsA(unreadable(
            'the atKeys file at an unresolved path',
            'The keys for $atSign in the atKeys file at an unresolved path '
                'could not be read: there is no home directory to find the '
                "keyfile in; give FileAtKeysIo the keyfile's path as filePath.",
            isA<AtException>())));
    expectNothingSent();
  });

  test(
      'with no home directory, the default keyfile path refuses every read '
      'and write, saying so', () async {
    final keys =
        FileAtKeysIo(filePath: (a) => defaultAtKeysFilePathUnder(null, a));
    final saysSo = throwsA(isA<AtException>().having(
        (e) => e.message, 'message', startsWith('there is no home directory')));

    await expectLater(keys.read(atSign), saysSo);
    await expectLater(keys.checkWritable(atSign), saysSo);
    await expectLater(keys.write(atSign, AtKeys()), saysSo);
    await expectLater(keys.flush(atSign.toAtsign(), AtKeys()), saysSo);
    await expectLater(keys.update(atSign.toAtsign(), (_) => true), saysSo);
    expect(defaultAtKeysFilePathUnder('/home/alice', atSign),
        getDefaultAtKeysFilePath('/home/alice', atSign),
        reason: 'the control: with a home directory, the default path');
  });

  group('Given a process with no home directory', () {
    /// What the support program prints after reading keys for [atSign]
    /// through a `FileAtKeysIo` built with no file path, run with neither
    /// HOME nor USERPROFILE set, or with the platform's one set to [home].
    Future<String> readThroughTheDefaultPath({String? home}) async {
      final environment = Map.of(Platform.environment)
        ..remove('HOME')
        ..remove('USERPROFILE');
      if (home != null) {
        environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] = home;
      }
      final packageConfig = await Isolate.packageConfig;
      final result = await Process.run(
          Platform.resolvedExecutable,
          [
            if (packageConfig != null)
              '--packages=${packageConfig.toFilePath()}',
            File('test/support/read_keyfile_with_default_path.dart')
                .absolute
                .path,
            atSign,
          ],
          environment: environment,
          includeParentEnvironment: false);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      return result.stdout as String;
    }

    test(
        'when a FileAtKeysIo built with no file path reads keys, then it '
        'refuses, saying there is no home directory', () async {
      expect(
          await readThroughTheDefaultPath(),
          contains('AtException: there is no home directory to find the '
              "keyfile in; give FileAtKeysIo the keyfile's path as filePath"));
      expect(await readThroughTheDefaultPath(home: dir.path),
          allOf(contains(dir.path), isNot(contains('no home directory'))),
          reason: 'the control: with a home directory, the read looks under '
              'it');
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

  group(
      'Activation with no keys store, or a read-only one, is refused before '
      'anything is sent', () {
    Future<AtOnboardingResponse> onboardInto(AtKeysIo? keys) => atAuth.onboard(
        AtOnboardingRequest(atSign,
            signingAlgoType: SigningAlgoType.rsa2048, atKeysIo: keys),
        cramSecret);

    final saysWhereTheKeysGo = isA<AtAuthenticationException>().having(
        (e) => e.message,
        'message',
        contains('set AtOnboardingRequest.atKeysIo'));

    test('no atKeysIo', () async {
      await expectLater(onboardInto(null), throwsA(saysWhereTheKeysGo));
      expectNothingSent();
    });

    test('a read-only atKeysIo', () async {
      await expectLater(
          onboardInto(_ReadOnlyStore()),
          throwsA(saysWhereTheKeysGo.having(
              (e) => e.message, 'read-only', contains('is read-only'))));
      expectNothingSent();
    });
  });

  group(
      'Two checks that one keyfile path can be written, run at once, both '
      'succeed', () {
    test('and nothing is left behind', () async {
      final io =
          FileAtKeysIo(filePath: (_) => '${dir.path}/${atSign}_key.atKeys');

      final outcomes = await Future.wait([
        for (var i = 0; i < 2; i++)
          io
              .checkWritable(atSign)
              .then<Object?>((_) => null, onError: (Object e) => e),
      ]);

      expect(outcomes, [null, null],
          reason: 'two checks of one keyfile path at once each succeed');
      expect(dir.listSync(), isEmpty,
          reason: 'neither check leaves a file behind');
    });
  });

  group('A keyfile path that is a directory', () {
    test('is refused as not writable, leaving the directory as it was',
        () async {
      final path = '${dir.path}/${atSign}_key.atKeys';
      Directory(path).createSync();

      await expectLater(
          FileAtKeysIo(filePath: (_) => path).checkWritable(atSign),
          throwsA(isA<FileSystemException>()
              .having((e) => e.path, 'path', path)
              .having((e) => e.message, 'message',
                  startsWith('Cannot write the atKeys file: '))));
      expect(dir.listSync().map((e) => e.path), [path],
          reason: 'the check leaves no probe file behind');
    });

    test('is refused before anything is sent to the atServer', () async {
      final path = '${dir.path}/${atSign}_key.atKeys';
      Directory(path).createSync();

      await expectLater(activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(isA<FileSystemException>()));
      expectNothingSent();
    });
  });

  /// The probe files each check run through [probing] creates.
  final probes = <String>[];

  /// Checks that [path] can be written, recording in [probes] each probe
  /// file the check creates, whose delete is refused unless [deletable].
  Future<void> probing(String path, {required bool deletable}) {
    probes.clear();
    return IOOverrides.runZoned(
        () => FileAtKeysIo(filePath: (_) => path).checkWritable(atSign),
        createFile: (p) {
      // NOTE: the real file, made outside these overrides.
      final file = Zone.root.run(() => File(p));
      if (!p.startsWith('$path.writable.')) return file;
      probes.add(p);
      return _ProbeFile(file, deletable: deletable);
    });
  }

  test('The writability check removes the file it creates to find out',
      () async {
    await probing('${dir.path}/${atSign}_key.atKeys', deletable: true);

    expect(probes, hasLength(1),
        reason: 'the control: the check created a probe file');
    expect(dir.listSync(), isEmpty,
        reason: 'the check leaves nothing in the directory it checked');
  });

  test('A writability check whose probe cannot be deleted says so', () async {
    final path = '${dir.path}/${atSign}_key.atKeys';

    await expectLater(
        probing(path, deletable: false),
        throwsA(isA<FileSystemException>()
            .having((e) => e.path, 'path', path)
            .having((e) => e.message, 'message',
                startsWith('Cannot write the atKeys file: '))));
    expect(probes, hasLength(1),
        reason: 'the control: the check created a probe file');
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

  group('Activation refuses unusable keys with AtKeysUnusableException', () {
    const source = 'the test keys store';

    test('a keyfile with a field of the wrong type', () async {
      final path = '${dir.path}/${atSign}_key.atKeys';
      final selfEncryptionKey = randomBase64(32);
      await File(path).writeAsString(jsonEncode(
          {'selfEncryptionKey': selfEncryptionKey, 'aesPkamPublicKey': 5}));

      await expectLater(
          activate(FileAtKeysIo(filePath: (_) => path)),
          throwsA(allOf(
              unreadable(
                  path,
                  "The keys for $atSign at $path could not be read: type 'int' "
                  "is not a subtype of type 'String' in type cast.",
                  isA<TypeError>()),
              holdsNoneOf(selfEncryptionKey))));
      expectNothingSent();
    });

    test('a keychain the platform refuses to read', () async {
      await expectLater(
          activate(_UnreadableStore(_PlatformRefusal(),
              source: "this device's keychain")),
          throwsA(unreadable(
              "this device's keychain",
              "The keys for $atSign in this device's keychain could not be "
                  'read: PlatformException(AuthError:UserCanceled, User '
                  'canceled the operation., null, null).',
              isA<_PlatformRefusal>())));
      expectNothingSent();
    });

    test('a store whose entry is not JSON', () async {
      await expectLater(
          activate(_UnreadableStore(AtKeysFormatException.notJson('the entry',
              const FormatException('Unexpected character', null, 0)))),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: it is not '
              'valid JSON: Unexpected character (at character 1).',
              isA<AtKeysFormatException>())));
      expectNothingSent();
    });

    test('a store whose entry is not a JSON object', () async {
      await expectLater(
          activate(
              _UnreadableStore(AtKeysFormatException.notAnObject('the entry'))),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: it is not a '
              'JSON object.',
              isA<AtKeysFormatException>())));
      expectNothingSent();
    });

    test('a FormatException, whose text is not repeated', () async {
      final text = '{"aesPkamPrivateKey": "${randomBase64(32)}"';
      final error =
          FormatException('Unexpected end of input', text, text.length);

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(allOf(
              unreadable(
                  source,
                  'The keys for $atSign in $source could not be read: '
                  'Unexpected end of input.',
                  isA<FormatException>()
                      .having((e) => e.message, 'message',
                          'Unexpected end of input')
                      .having((e) => e.source, 'source', isNull)
                      .having((e) => e.offset, 'offset', text.length)),
              isA<AtKeysUnusableException>()
                  .having((e) => e.message, 'message', holdsNoneOf(text))
                  .having((e) => '${e.error}', 'error', holdsNoneOf(text)))));
      expectNothingSent();
    });

    test('an AtException, whose message is the reason', () async {
      final error = AtKeysValidationException('Unsupported atKeys version: 2');

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: Unsupported '
              'atKeys version: 2.',
              same(error))));
      expectNothingSent();
    });

    test('a reason that ends in a full stop keeps one', () async {
      final error = AtKeysValidationException('The store is closed.');

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: The store is '
              'closed.',
              same(error))));
      expectNothingSent();
    });

    test('a parser reason that reads like not an object, at a position',
        () async {
      await expectLater(
          activate(_UnreadableStore(AtKeysFormatException.notJson('the entry',
              const FormatException('not a JSON object', null, 3)))),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: it is not '
              'valid JSON: not a JSON object (at character 4).',
              isA<AtKeysFormatException>())));
      expectNothingSent();
    });

    test('an error whose text spans lines gives its first line', () async {
      final error = StateError('the store is closed\n#0 main (file.dart:1)');

      await expectLater(
          activate(_UnreadableStore(error)),
          throwsA(unreadable(
              source,
              'The keys for $atSign in $source could not be read: Bad state: '
              'the store is closed.',
              same(error))));
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
