import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/keys/io/default_keyfile_path.dart';
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

/// Matches a refusal to decrypt that does not say the passphrase is wrong or
/// missing.
final notAPassphraseRefusal = allOf(
    isA<AtDecryptionException>(), isNot(isA<AtKeysPassphraseException>()));

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

  /// Holds [atSign] online on this device from a keyfile at the test's
  /// path written with [passPhrase], then leaves the keyfile as [unreadable]
  /// makes it and opens [atSign] from what [reader] reads; expects the open
  /// to fail with [cause] and a message that [says] what is wrong, whose
  /// reason matches [reason], holding no [window]-character run of the text
  /// [unreadable] returns.
  Future<void> refusedAfterOnline(
      {String? passPhrase,
      AtKeysUnusableCause cause = AtKeysUnusableCause.unreadable,
      String says = 'could not be read',
      required Future<String> Function() unreadable,
      int window = 16,
      required AtKeysIo reader,
      required Matcher reason,
      Matcher error = anything}) async {
    final pref = await preference();
    await FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase)
        .write(atSign, liveKeys());
    final first = await Atsign(atSign).open(
        keys: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
        preference: pref,
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref),
        atLookUp: lookUpAnswering(() async => true),
        storage: hiveStoreFor(atSign, pref));
    expect(first.connection.current.isOnline, isTrue,
        reason: 'the precondition: this device has held the atSign online');
    await first.stop();

    final secret = await unreadable();
    final prefix = 'The keys for $atSign in the AtKeys store ($path) $says: ';
    await expectLater(
        Atsign(atSign).open(
            keys: reader,
            preference: pref,
            lookUps: recordingLookUps,
            secondaryAddressFinder: atDirectory,
            storage: hiveStoreFor(atSign, pref)),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', cause)
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
            .having((e) => e.message, 'what was read',
                holdsNoRunOf(secret, window: window))));
    expectNoConnection();
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
                'No keys for $atSign in the AtKeys store ($path), so this '
                    'device cannot authenticate as $atSign. Activate '
                    '$atSign, enroll this device, or use the keyfile it '
                    'already has.')));
    expectNoConnection();
  });

  test('A keyfile path that cannot be resolved is refused before connecting',
      () async {
    await expectLater(
        openUnconnected(
            FileAtKeysIo(filePath: (a) => defaultAtKeysFilePathUnder(null, a))),
        throwsA(isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.unreadable)
            .having((e) => e.source, 'source',
                'the atKeys file at an unresolved path')
            .having((e) => e.message, 'message',
                contains('there is no home directory to find the keyfile in'))
            .having((e) => e.error, 'error', isA<AtException>())));
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

    test('a keyId that appears twice', () async {
      final keyId = randomBase64(24);
      await refusedAfterOnline(
          unreadable: () async {
            final document = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final enrollment =
                (document['enrollments'] as List).first as Map<String, dynamic>;
            final keys = enrollment['keys'] as List;
            final entry = keys.first as Map<String, dynamic>;
            entry['keyId'] = keyId;
            keys.add(Map<String, dynamic>.of(entry));
            File(path).writeAsStringSync(jsonEncode(document));
            return keyId;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: startsWith('Duplicate atKeys keyId at '),
          error: isA<AtKeysValidationException>());
    });

    test('an envelope version this build has no code for', () async {
      final version = randomBase64(24);
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            envelope['v'] = version;
            File(path).writeAsStringSync(jsonEncode(envelope));
            return version;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: contains('an envelope version this build has no code for'),
          error: notAPassphraseRefusal);
    });

    for (final (name, field, says) in [
      ('salt', 'salt', 'must carry a salt'),
      ('key derivation parameters', 'kdfParams', 'must carry kdfParams'),
    ]) {
      test('an envelope that carries no $name', () async {
        await refusedAfterOnline(
            passPhrase: passPhrase,
            unreadable: () async {
              final envelope = jsonDecode(File(path).readAsStringSync())
                  as Map<String, dynamic>;
              expect(envelope.remove(field), isNotNull,
                  reason: 'the precondition: the envelope carried $field');
              File(path).writeAsStringSync(jsonEncode(envelope));
              return envelope['content'] as String;
            },
            reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
            reason: contains(says),
            error: notAPassphraseRefusal);
      });
    }

    test('a role that appears twice for one keyId', () async {
      final value = randomBase64(24);
      await refusedAfterOnline(
          unreadable: () async {
            final document = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final enrollment =
                (document['enrollments'] as List).first as Map<String, dynamic>;
            final entry =
                (enrollment['keys'] as List).first as Map<String, dynamic>;
            entry['keyId'] = value;
            final material = entry['material'] as List;
            final part = material.first as Map<String, dynamic>;
            part['role'] = value;
            material.add(Map<String, dynamic>.of(part));
            File(path).writeAsStringSync(jsonEncode(document));
            return value;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: startsWith('Duplicate role at '),
          error: isA<AtKeysValidationException>());
    });

    test('an enrollment holding two active keys of one role and algorithm',
        () async {
      final value = randomBase64(24);
      await refusedAfterOnline(
          unreadable: () async {
            final document = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final enrollment =
                (document['enrollments'] as List).first as Map<String, dynamic>;
            enrollment['enrollmentId'] = value;
            final keys = enrollment['keys'] as List;
            final entry = keys.first as Map<String, dynamic>;
            final part =
                (entry['material'] as List).first as Map<String, dynamic>;
            part['role'] = value;
            part['algorithm'] = value;
            keys.add({...entry, 'keyId': randomBase64(12)});
            File(path).writeAsStringSync(jsonEncode(document));
            return value;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: startsWith('an enrollment holds more than one active key '
              'material of one role and algorithm'),
          error: isA<AtKeysEnrollmentException>());
    });

    test('an atKeys version this build has no code for', () async {
      final version = '${random.nextInt(900000000) + 100000000}'
          '${random.nextInt(900000000) + 100000000}';
      await refusedAfterOnline(
          unreadable: () async {
            final document = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            document['version'] = int.parse(version);
            File(path).writeAsStringSync(jsonEncode(document));
            return version;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: startsWith('this atKeys file declares a version this build '
              'has no code for'),
          error: isA<AtKeysUnsupportedVersionException>());
    });

    test('a namespace that names no string', () async {
      final namespace = randomBase64(24);
      await refusedAfterOnline(
          unreadable: () async {
            final document = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final enrollment =
                (document['enrollments'] as List).first as Map<String, dynamic>;
            enrollment['namespaces'] = {namespace: 5};
            File(path).writeAsStringSync(jsonEncode(document));
            return namespace;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: startsWith('Expected string in enrollments[0].namespaces'),
          error: isA<AtKeysParseException>());
    });

    for (final name in const ['memory', 'iterations', 'parallelism']) {
      test('a key derivation $name below one', () async {
        final cost = '-${random.nextInt(900000000) + 100000000}'
            '${random.nextInt(900000000) + 100000000}';
        await refusedAfterOnline(
            passPhrase: passPhrase,
            unreadable: () async {
              final envelope = jsonDecode(File(path).readAsStringSync())
                  as Map<String, dynamic>;
              (envelope['kdfParams'] as Map<String, dynamic>)[name] =
                  int.parse(cost);
              File(path).writeAsStringSync(jsonEncode(envelope));
              return cost;
            },
            reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
            reason: contains('must carry a positive integer kdfParams.$name'),
            error: notAPassphraseRefusal);
      });
    }

    test('a key derivation cost that is a string', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams['iterations'] = '3';
            File(path).writeAsStringSync(jsonEncode(envelope));
            return passPhrase;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason:
              contains('must carry a positive integer kdfParams.iterations'),
          error: notAPassphraseRefusal);
    });

    test('a key derivation cost that is not a whole number', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams['parallelism'] = 1.5;
            File(path).writeAsStringSync(jsonEncode(envelope));
            return passPhrase;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason:
              contains('must carry a positive integer kdfParams.parallelism'),
          error: notAPassphraseRefusal);
    });

    test('a key derivation with no memory', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams.remove('memory');
            File(path).writeAsStringSync(jsonEncode(envelope));
            return passPhrase;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: contains('must carry a positive integer kdfParams.memory'),
          error: notAPassphraseRefusal);
    });

    test('a key derivation memory and parallelism of zero', () async {
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams['memory'] = 0;
            kdfParams['parallelism'] = 0;
            File(path).writeAsStringSync(jsonEncode(envelope));
            return passPhrase;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: contains('must carry a positive integer kdfParams.memory'),
          error: notAPassphraseRefusal);
    });

    test('a key derivation memory below eight times its parallelism', () async {
      final cost = '${random.nextInt(90000000) + 10000000}'
          '${random.nextInt(900000000) + 100000000}';
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams['memory'] = int.parse(cost);
            kdfParams['parallelism'] = int.parse(cost);
            File(path).writeAsStringSync(jsonEncode(envelope));
            return cost;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: contains('kdfParams.memory of at least 8 times its '
              'kdfParams.parallelism'),
          error: notAPassphraseRefusal);
    });

    test('a key derivation this device cannot run', () async {
      final memory = 4 *
          ((random.nextInt(9000) + 1000) * 1000000000 +
              random.nextInt(1000000000));
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            final kdfParams = envelope['kdfParams'] as Map<String, dynamic>;
            kdfParams['memory'] = memory;
            kdfParams['parallelism'] = 1;
            File(path).writeAsStringSync(jsonEncode(envelope));
            // NOTE: both values; a 13-character window fits inside either.
            return '$memory ${memory * 1024}';
          },
          window: 13,
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: startsWith('this atKeys file asks for a key derivation this '
              'device could not run'),
          error: notAPassphraseRefusal);
    });

    test('a hashing algorithm this build has no code for', () async {
      final name = randomBase64(24);
      await refusedAfterOnline(
          passPhrase: passPhrase,
          unreadable: () async {
            final envelope = jsonDecode(File(path).readAsStringSync())
                as Map<String, dynamic>;
            envelope['hashingAlgoType'] = name;
            File(path).writeAsStringSync(jsonEncode(envelope));
            return name;
          },
          reader: FileAtKeysIo(filePath: (_) => path, passPhrase: passPhrase),
          reason: startsWith('this atKeys file names a hashingAlgoType this '
              'build has no code for'),
          error: notAPassphraseRefusal);
    });
  });

  group(
      'Keys that hold no authentication keypair this device can use are '
      'refused before connecting, even on a device that has held the atSign '
      'online', () {
    Future<void> refusedWithNoKeypair(
            {required Future<String> Function() unreadable,
            required AtKeysIo reader,
            required Matcher reason,
            required Matcher error}) =>
        refusedAfterOnline(
            cause: AtKeysUnusableCause.noAuthenticationKeypair,
            says: 'cannot be used to authenticate',
            unreadable: unreadable,
            reader: reader,
            reason: reason,
            error: error);

    test('an algorithm this build cannot sign with', () async {
      final algorithm =
          'future-${List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join()}';
      final privateKey = randomBase64(32);
      await refusedWithNoKeypair(
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
                      algorithm: CryptographicMaterialAlgorithm.of(algorithm),
                      publicKey: randomBase64(32),
                      privateKey: privateKey));
            return privateKey;
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: contains('authenticates with "$algorithm", which this build '
              'cannot sign with'),
          error: isA<AtKeyNotFoundException>());
    });

    test('no authentication keypair', () async {
      final privateKey = randomBase64(64);
      await refusedWithNoKeypair(
          unreadable: () async {
            File(path).deleteSync();
            await FileAtKeysIo(filePath: (_) => path).write(
                atSign,
                AtKeys.legacy(
                    apkamPrivateKey: privateKey,
                    encryptionPublicKey: randomBase64(64),
                    encryptionPrivateKey: randomBase64(64),
                    selfEncryptionKey: randomBase64(32)));
            return File(path).readAsStringSync();
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: equals('AtKeys holds no authentication keypair for the '
              'enrollment it authenticates as, so there is nothing to sign '
              'with'),
          error: isA<AtKeyNotFoundException>());
    });

    test('several enrollments qualifying', () async {
      await refusedWithNoKeypair(
          unreadable: () async {
            final document = (liveKeys(enrollmentId: 'e-one')
                  ..atsign = atSign.toAtsign())
                .toJson();
            final other = (liveKeys(enrollmentId: 'e-two')
                  ..atsign = atSign.toAtsign())
                .toJson();
            (document['enrollments'] as List)
                .addAll(other['enrollments'] as List);
            File(path).writeAsStringSync(jsonEncode(document));
            return File(path).readAsStringSync();
          },
          reader: FileAtKeysIo(filePath: (_) => path),
          reason: allOf(contains('e-one'), contains('e-two'),
              contains('is not derivable')),
          error: isA<AtKeysEnrollmentException>());
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
            .having(
                (e) => e.message,
                'message',
                'The keys in the AtKeys store ($path) are for @bob, not '
                    '$atSign.')));
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
        lookUps: loopbackLookUps(),
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
    final pendingPath = '${dir.path}/keys/pending_key.atKeys';
    await FileAtKeysIo(filePath: (_) => path).write(atSign, AtKeys());
    await FileAtKeysIo(filePath: (_) => pendingPath).write(atSign, pending);

    AtNoCredentialException? noCredential;
    try {
      await openUnconnected(FileAtKeysIo(filePath: (_) => path));
    } on AtNoCredentialException catch (e) {
      noCredential = e;
    }
    AtEnrollmentPendingException? onlyPending;
    try {
      await openUnconnected(FileAtKeysIo(filePath: (_) => pendingPath));
    } on AtEnrollmentPendingException catch (e) {
      onlyPending = e;
    }

    expect(
        noCredential,
        isA<AtKeysUnusableException>()
            .having((e) => e.cause, 'cause', AtKeysUnusableCause.noCredential)
            .having((e) => e.source, 'source', path)
            .having(
                (e) => e.message,
                'message',
                '$atSign holds no credential in the AtKeys store ($path): its '
                    'enrollment was denied, cancelled or expired, or never '
                    'completed, so there is nothing to authenticate with; '
                    'enroll again'));
    expect(
        onlyPending,
        isA<AtEnrollmentPendingException>()
            .having(
                (e) => e.cause, 'cause', AtKeysUnusableCause.pendingEnrollment)
            .having((e) => e.source, 'source', pendingPath)
            .having(
                (e) => e.message,
                'message',
                '$atSign holds no live credential in the AtKeys store '
                    '($pendingPath), only the pending enrollment "e-1": '
                    'resume it with resumeEnrollment rather than opening it')
            .having((e) => e.pendingEnrollmentIds, 'pending', ['e-1']));
    expectNoConnection();
  });

  test('An atServer refusal still says the atServer refused it', () async {
    final pref = await preference();
    final revoked = lookUpAnswering(() async => throw AtAuthErrorReplyException(
        'Failed connecting to $atSign. error:AT0027:Apkam Access Revoked',
        errorCode: 'AT0027'));

    await expectLater(
        Atsign(atSign).open(
            keys: InMemoryAtKeysIo.holding(atSign, liveKeys()),
            preference: pref,
            lookUps: loopbackLookUps(),
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
        lookUps: loopbackLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        storage: hiveStoreFor(atSign, pref));

    expect(client.connection.current.isOffline, isTrue);
    expect(client.connection.current.cause, AtConnectionCause.unreachable);
  });

  test(
      'Enrolling into a store that holds live keys says to give the '
      'enrollment a store of its own', () async {
    await FileAtKeysIo(filePath: (_) => path).write(atSign, liveKeys());
    final pref = await preference();

    await expectLater(
        Atsign(atSign).enroll(
            otp: 'ABC123',
            app: 'wavi',
            device: 'phone',
            namespaces: const {'wavi': 'rw'},
            keys: FileAtKeysIo(filePath: (_) => path),
            preference: pref,
            lookUps: recordingLookUps,
            secondaryAddressFinder: atDirectory),
        throwsA(isA<AtEnrollmentException>().having(
            (e) => e.message,
            'message',
            allOf(
                startsWith('Give a new enrollment an AtKeys store of its own: '
                    '$atSign already holds live keys in the AtKeys store '
                    '($path), and enrolling again'),
                isNot(contains('remove'))))),
        reason: 'the refusal starts with what to do, then names the keyfile '
            'holding the live keys, by its path in brackets');
    expectNoConnection();
  });

  group('Given an AtNoCredentialException for $atSign', () {
    test(
        "when its source is this device's keychain, then its message names "
        'the AtKeys store with the keychain in brackets', () {
      expect(
          AtNoCredentialException(atSign, source: "this device's keychain")
              .message,
          "$atSign holds no credential in the AtKeys store (this device's "
          'keychain): its enrollment was denied, cancelled or expired, or '
          'never completed, so there is nothing to authenticate with; enroll '
          'again');
    });

    test(
        'when it has no source, then its message names the AtKeys store with '
        'no brackets', () {
      expect(
          AtNoCredentialException(atSign).message,
          '$atSign holds no credential in the AtKeys store: its enrollment '
          'was denied, cancelled or expired, or never completed, so there is '
          'nothing to authenticate with; enroll again');
    });
  });
}
