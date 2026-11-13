import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart' show AtAuthenticator, AtLookupMuxable;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/hive_store.dart';
import '../test_utils/mocks.dart';
import '../test_utils/transport.dart';

class _FakeVerbBuilder extends Fake implements VerbBuilder {}

/// Matches text holding no run of [window] consecutive characters of [value].
Matcher holdsNoRunOf(String value, {int window = 16}) => predicate<String>(
    (text) => !Iterable.generate(value.length - window + 1)
        .any((i) => text.contains(value.substring(i, i + window))),
    'text holding no $window-character run of what was read');

/// An atDirectory that records each atSign it is asked for and answers none.
class _RecordingAtDirectory implements SecondaryAddressFinder {
  final List<String> asked = [];

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    asked.add(atSign);
    throw SecondaryNotFoundException('asked for $atSign');
  }
}

/// `Atsign.open` refuses keys it cannot use before it connects, and says why.
///
/// Catalogue: features/at_client/open_unusable_keys.feature
///
/// The atServer is a mocked lookup handed in through `atLookUp`; an open
/// that must make no connection is given a `lookUps` that records every
/// connection it is asked to build and an atDirectory that records every
/// atSign it is asked for.
void main() {
  const atSign = '@alice';
  final random = Random.secure();
  late Directory dir;
  late String path;
  late List<String> built;
  late _RecordingAtDirectory atDirectory;

  setUpAll(() => registerFallbackValue(_FakeVerbBuilder()));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_unusable_keys_');
    path = '${dir.path}/keys/${atSign}_key.atKeys';
    built = [];
    atDirectory = _RecordingAtDirectory();
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    await Process.run('chmod', ['-R', 'u+rwx', dir.path]);
    dir.deleteSync(recursive: true);
  });

  String randomBase64(int bytes) =>
      base64Encode(List.generate(bytes, (_) => random.nextInt(256)));

  Future<AtClientPreference> preference() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return AtClientPreference()
      ..rootDomain = InternetAddress.loopbackIPv4.address
      ..rootPort = port
      ..hiveStoragePath = '${dir.path}/storage'
      ..namespace = 'lifecycle';
  }

  /// Records each connection it is asked to build, and builds none.
  AtLookupMuxable recordingLookUps(
      {required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder}) {
    built.add(atSign);
    throw StateError('no connection was expected for $atSign');
  }

  /// A lookup whose PKAM attempt does what [onPkam] says.
  MockAtLookupImpl lookUpAnswering(Future<bool> Function() onPkam) {
    final lookUp = MockAtLookupImpl();
    when(() => lookUp.pkamAuthenticate()).thenAnswer((_) => onPkam());
    when(() => lookUp.close()).thenAnswer((_) async {});
    when(() => lookUp.isConnectionAvailable()).thenReturn(false);
    return lookUp;
  }

  /// Keys holding an active APKAM keypair for [enrollmentId] and the
  /// atSign's own keys, the private halves random.
  AtKeys liveKeys({String enrollmentId = 'e-live'}) {
    final now = DateTime.now().toUtc();
    CryptographicMaterial material(String keyId, String role, String algorithm,
            {String? enrollment}) =>
        CryptographicMaterial(
            keyId: keyId,
            enrollmentId: enrollment,
            role: CryptographicMaterialRole.of(role),
            algorithm: CryptographicMaterialAlgorithm.of(algorithm),
            bytes: AtBytes.fromString(randomBase64(32)),
            createdAt: now);
    return AtKeys()
      ..addKey(material(
          'apkam:$enrollmentId:1', 'privateAuthentication', 'mldsa65',
          enrollment: enrollmentId))
      ..addKey(material(
          'apkam:$enrollmentId:1', 'publicAuthentication', 'mldsa65',
          enrollment: enrollmentId))
      ..addKey(material('enc:rsa2048:1', 'publicEncryption', 'rsa2048'))
      ..addKey(material('enc:rsa2048:1', 'privateDecryption', 'rsa2048'))
      ..addKey(material('self:aes256:1', 'symmetricEncryption', 'aes256'));
  }

  /// Opens [atSign] on [keys] with nothing for a connection to reach.
  Future<AtClient> openUnconnected(AtKeysIo keys,
      {String atSign = atSign}) async {
    final pref = await preference();
    return Atsign(atSign).open(
        keys: keys,
        preference: pref,
        lookUps: recordingLookUps,
        secondaryAddressFinder: atDirectory,
        storage: hiveStoreFor(atSign, pref));
  }

  void expectNoConnection() {
    expect(built, isEmpty, reason: 'no connection is built');
    expect(atDirectory.asked, isEmpty, reason: 'the atDirectory is not asked');
  }

  test('An absent keyfile is refused before connecting', () async {
    await expectLater(
        openUnconnected(FileAtKeysIo(filePath: (_) => path)),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.absent)
            .having((e) => e.atSign, 'atSign', atSign)
            .having((e) => e.source, 'source', path)
            .having((e) => e.error, 'error', isA<AtKeysSourceAbsentException>())
            .having(
                (e) => e.message,
                'message',
                'No keys for $atSign at $path, so this device cannot '
                    'authenticate as $atSign. Activate $atSign, enroll this '
                    'device, or use the keyfile it already has.')));
    expectNoConnection();
  });

  group(
      'An unreadable keyfile is refused before connecting, even on a device '
      'that has held the atSign online', () {
    const passPhrase = 'passphrase-5b0e2c71';
    const otherPassPhrase = 'passphrase-c83a9d46';
    final runningAsRoot =
        (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
    final Object skipModes = Platform.isWindows
        ? 'needs POSIX file modes'
        : runningAsRoot
            ? 'root reads whatever the mode says'
            : false;

    /// Holds [atSign] online on this device from a keyfile at the test's
    /// path written with [passPhrase], then leaves the keyfile as [unreadable]
    /// makes it and opens [atSign] from what [reader] reads; expects the open
    /// to fail with cause unreadable and a message whose reason matches
    /// [reason], holding no 16-character run of the text [unreadable]
    /// returns.
    Future<void> refusedAfterOnline(
        {String? passPhrase,
        required Future<String> Function() unreadable,
        required AtKeysIo reader,
        required Matcher reason,
        Matcher error = anything}) async {
      final pref = await preference();
      await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase)
          .write(atSign, liveKeys());
      final first = await Atsign(atSign).open(
          keys: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          preference: pref,
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(pref),
          atLookUp: lookUpAnswering(() async => true),
          storage: hiveStoreFor(atSign, pref));
      expect(first.connection.current.isOnline, isTrue,
          reason: 'the precondition: this device has held the atSign online');
      await first.stop();

      final secret = await unreadable();
      final prefix = 'The keys for $atSign at $path could not be read: ';
      await expectLater(
          Atsign(atSign).open(
              keys: reader,
              preference: pref,
              lookUps: recordingLookUps,
              secondaryAddressFinder: atDirectory,
              storage: hiveStoreFor(atSign, pref)),
          throwsA(isA<AtKeysUnusableException>()
              .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
              .having((e) => e.source, 'source', path)
              .having((e) => e.error, 'error', error)
              .having(
                  (e) => e.message,
                  'message',
                  allOf(
                      startsWith(prefix),
                      endsWith('.'),
                      predicate<String>(
                          (m) => reason.matches(
                              m.substring(prefix.length, m.length - 1), {}),
                          'a reason that $reason')))
              .having(
                  (e) => e.message, 'what was read', holdsNoRunOf(secret))));
      expectNoConnection();
    }

    test('permission denied', () async {
      await refusedAfterOnline(
          unreadable: () async {
            final text = File(path).readAsStringSync();
            expect(Process.runSync('chmod', ['000', path]).exitCode, 0);
            return text;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: contains('Permission denied'),
          error: isA<FileSystemException>());
    }, skip: skipModes);

    test('not a JSON object', () async {
      final secret = randomBase64(24);
      await refusedAfterOnline(
          unreadable: () async {
            File(path).writeAsStringSync(jsonEncode([secret]));
            return secret;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: equals('it is not a JSON object'),
          error: isA<AtKeysFormatException>());
    });

    test('wrong passphrase', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async => File(path).readAsStringSync(),
          reader:
              FileAtKeysIo(filePath: (_) => path, passPhrase: otherPassPhrase),
          reason: allOf(
              startsWith(
                  'Failed to decrypt atKeys file - passphrase may be incorrect'),
              isNot(contains(passPhrase)),
              isNot(contains(otherPassPhrase))),
          error: isA<AtDecryptionException>());
    });

    test('no passphrase', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async => File(path).readAsStringSync(),
          reader: FileAtKeysIo(filePath: (_) => path),
          reason:
              equals('Pass Phrase is required for password protected atKeys '
                  'file'),
          error: isA<AtDecryptionException>());
    });

    test('unsupported algorithm', () async {
      final privateKey = randomBase64(32);
      await refusedAfterOnline(
          unreadable: () async {
            File(path).deleteSync();
            await FileAtKeysIo(filePath: (_) => path).write(
                atSign,
                AtKeys.legacy(
                    apkamPublicKey: randomBase64(64),
                    apkamPrivateKey: randomBase64(64),
                    encryptionPublicKey: randomBase64(64),
                    encryptionPrivateKey: randomBase64(64),
                    selfEncryptionKey: randomBase64(32))
                  ..fileApkamMaterial(
                      enrollmentId: 'future-algorithm',
                      algorithm: CryptographicMaterialAlgorithm.of(
                          'sphincs-plus-256s'),
                      publicKey: randomBase64(32),
                      privateKey: privateKey));
            return privateKey;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: contains(
              '"sphincs-plus-256s", which this build cannot sign with'),
          error: isA<AtKeyNotFoundException>());
    });

    test('a field of the wrong type', () async {
      final selfEncryptionKey = randomBase64(32);
      await refusedAfterOnline(
          unreadable: () async {
            File(path).writeAsStringSync(jsonEncode({
              'selfEncryptionKey': selfEncryptionKey,
              'aesPkamPublicKey': 5
            }));
            return selfEncryptionKey;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: equals(
              "type 'int' is not a subtype of type 'String' in type cast"),
          error: isA<TypeError>());
    });
  });

  test('A keyfile naming another atSign is refused before connecting',
      () async {
    await FileAtKeysIo(filePath: (_) => path).write('@bob', liveKeys());
    expect(
        (await FileAtKeysIo(filePath: (_) => path).read(atSign)).atsign, '@bob',
        reason: 'the precondition: the keyfile records @bob');

    await expectLater(
        openUnconnected(FileAtKeysIo(filePath: (_) => path)),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.anotherAtsign)
            .having((e) => e.source, 'source', path)
            .having((e) => e.message, 'message',
                'The keys at $path are for @bob, not $atSign.')));
    expectNoConnection();
  });

  test('A keyfile that names no atSign is used as before', () async {
    final keys = InMemoryAtKeysIo.holding(atSign, liveKeys());
    expect((await keys.read(atSign)).atsign, isNull,
        reason: 'the precondition: the keys record no atSign');
    final lookUp = lookUpAnswering(() async => true);
    final pref = await preference();

    final client = await Atsign(atSign).open(
        keys: keys,
        preference: pref,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref),
        atLookUp: lookUp,
        storage: hiveStoreFor(atSign, pref));

    expect(client.connection.current.isOnline, isTrue);
    expect(client.enrollmentId, 'e-live',
        reason: 'the client runs as the enrollment the keys hold');
    verify(() => lookUp.pkamAuthenticate()).called(1);
  });

  test(
      'Keys with no credential, or only a pending enrollment, are '
      'AtKeysUnusableExceptions', () async {
    final pending = AtKeys()
      ..addKey(CryptographicMaterial(
          keyId: 'apkam:e-1:1',
          enrollmentId: 'e-1',
          role: CryptographicMaterialRole.privateAuthentication,
          algorithm: CryptographicMaterialAlgorithm.mlDsa65,
          bytes: AtBytes(Uint8List.fromList(List<int>.filled(32, 3))),
          createdAt: DateTime.now().toUtc(),
          status: CryptographicMaterialStatus.pending));

    AtNoCredentialException? noCredential;
    try {
      await openUnconnected(InMemoryAtKeysIo.holding(atSign, AtKeys()));
    } on AtNoCredentialException catch (e) {
      noCredential = e;
    }
    AtEnrollmentPendingException? onlyPending;
    try {
      await openUnconnected(InMemoryAtKeysIo.holding(atSign, pending));
    } on AtEnrollmentPendingException catch (e) {
      onlyPending = e;
    }

    expect(
        noCredential,
        isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.noCredential)
            .having(
                (e) => e.message,
                'message',
                '$atSign holds no credential in this keyfile: its enrollment '
                    'was denied, cancelled or expired, or never completed, so '
                    'there is nothing to authenticate with; enroll again'));
    expect(
        onlyPending,
        isA<AtEnrollmentPendingException>()
            .having(
                (e) => e.cause, 'cause', AtKeysUnusableCause.pendingEnrollment)
            .having(
                (e) => e.message,
                'message',
                '$atSign holds no live credential, only the pending '
                    'enrollment e-1: resume it with resumeEnrollment rather '
                    'than opening it')
            .having((e) => e.pendingEnrollmentIds, 'pending', ['e-1']));
    expectNoConnection();
  });

  test('An atServer refusal still says the atServer refused it', () async {
    final pref = await preference();
    final revoked = lookUpAnswering(() async => throw UnAuthenticatedException(
        'Failed connecting to $atSign. error:AT0027:Apkam Access Revoked'));

    await expectLater(
        Atsign(atSign).open(
            keys: InMemoryAtKeysIo.holding(atSign, liveKeys()),
            preference: pref,
            lookUps: secureSocketLookUps(),
            secondaryAddressFinder: atDirectoryOf(pref),
            atLookUp: revoked,
            storage: hiveStoreFor(atSign, pref)),
        throwsA(isA<AtOpenRefusedException>()
            .having((e) => e.state.cause, 'cause', AtConnectionCause.revoked)
            .having((e) => e.message, 'message',
                contains('the atServer refused it (revoked)'))));
  });

  test('A readable keyfile with the atServer unreachable still opens offline',
      () async {
    await FileAtKeysIo(filePath: (_) => path).write(atSign, liveKeys());
    final pref = await preference();

    final client = await Atsign(atSign).open(
        keys: FileAtKeysIo(filePath: (_) => path),
        preference: pref,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        storage: hiveStoreFor(atSign, pref));

    expect(client.connection.current.isOffline, isTrue);
    expect(client.connection.current.cause, AtConnectionCause.unreachable);
  });

  test(
      'Enrolling into a store that holds live keys says to give the '
      'enrollment a store of its own', () async {
    final pref = await preference();

    await expectLater(
        Atsign(atSign).enroll(
            otp: 'ABC123',
            app: 'wavi',
            device: 'phone',
            namespaces: const {'wavi': 'rw'},
            keys: InMemoryAtKeysIo.holding(atSign, liveKeys()),
            preference: pref,
            lookUps: recordingLookUps,
            secondaryAddressFinder: atDirectory),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message,
            'message',
            allOf(endsWith('give a new enrollment a keys store of its own'),
                isNot(contains('remove'))))));
    expectNoConnection();
  });
}
