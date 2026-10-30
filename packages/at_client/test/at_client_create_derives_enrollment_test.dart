import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';
import 'test_utils/hive_store.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

/// `AtClientImpl.create` runs a client as the enrollment its keys authenticate
/// as, and a caller's disagreeing id loses.
void main() {
  const atSign = '@derivesenrollment';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('derives_enrollment_');
    AtClientImpl.atClientInstanceMap.clear();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    await HiveInstances.closeAll();
    await Hive.close();
    AtClientImpl.atClientInstanceMap.clear();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  AtClientPreference pref() => AtClientPreference(posture: PqPosture.legacy)
    ..isLocalStoreRequired = true
    ..hiveStoragePath = dir.path;

  String b64(String s) => base64Encode(utf8.encode(s));

  Future<InMemoryAtKeysIo> keyfile({String? flatEnrollmentId}) async {
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys.legacy(
            apkamPublicKey: b64('apkam-public'),
            apkamPrivateKey: b64('apkam-private'),
            encryptionPublicKey: b64('enc-public'),
            encryptionPrivateKey: b64('enc-private'),
            selfEncryptionKey: b64('self-key'),
            enrollmentId: flatEnrollmentId));
    return io;
  }

  test('a legacy keyfile runs the client as its flat stored enrollment',
      () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref()),
        atKeysIo: await keyfile(flatEnrollmentId: 'stored-1'),
        storage: hiveStoreFor(atSign, pref()));
    expect(client.enrollmentId, 'stored-1');
  });

  test('a disagreeing id is ignored and the keys win', () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref()),
        atKeysIo: await keyfile(flatEnrollmentId: 'stored-1'),
        enrollmentId: 'somebody-else',
        storage: hiveStoreFor(atSign, pref()));
    expect(client.enrollmentId, 'stored-1',
        reason: 'the keys decide; a caller cannot run a client as an '
            'enrollment its keys do not authenticate as');
    expect(AtClientImpl.atClientInstanceMap.keys,
        contains(AtClientImpl.instanceKey(atSign, 'stored-1')),
        reason: 'and it is filed under the enrollment it actually runs as');
  });

  test('a document holding no authentication material names no enrollment',
      () async {
    final io = InMemoryAtKeysIo();
    await io.write(atSign, AtKeys());
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref()),
        atKeysIo: io,
        enrollmentId: 'apkam-1',
        storage: hiveStoreFor(atSign, pref()));
    expect(client.enrollmentId, 'apkam-1',
        reason: 'no material, so nothing to derive from; the caller\'s id '
            'is the credential\'s');
  });

  test('a keyfile that predates enrollments runs the client as primary',
      () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: atDirectoryOf(pref()),
        atKeysIo: await keyfile(),
        storage: hiveStoreFor(atSign, pref()));
    expect(client.enrollmentId, 'primary');
  });

  group('a caller naming no enrollment, with one enrolled client cached', () {
    Future<AtClient> create(
            {String? enrollmentId,
            required AtClientStorage storage,
            bool? exactEnrollment}) =>
        exactEnrollment == null
            ? AtClientImpl.create(atSign, 'wavi', pref(),
                lookUps: secureSocketLookUps(),
                secondaryAddressFinder: atDirectoryOf(pref()),
                atKeysIo: noKeysFor(atSign),
                enrollmentId: enrollmentId,
                storage: storage)
            : AtClientImpl.create(atSign, 'wavi', pref(),
                lookUps: secureSocketLookUps(),
                secondaryAddressFinder: atDirectoryOf(pref()),
                atKeysIo: noKeysFor(atSign),
                enrollmentId: enrollmentId,
                storage: storage,
                exactEnrollment: exactEnrollment);

    InMemoryAtClientStorage store() =>
        InMemoryAtClientStorage(atSign: atSign, closedByClient: true);

    test('is not handed that enrollment\'s client', () async {
      final enrolled = await create(enrollmentId: 'e1', storage: store());

      Object? outcome;
      try {
        outcome = await create(storage: store());
      } catch (e) {
        outcome = e;
      }

      expect(
          outcome,
          isA<AtClientImpl>()
              .having((c) => c.enrollmentId, 'enrollmentId', isNull),
          reason: 'a caller naming no enrollment runs as the atSign\'s own '
              'credential, not as the one enrollment already cached');
      expect(identical(outcome, enrolled), isFalse);
    });

    test('is handed it when it passes exactEnrollment: false', () async {
      final storage = store();
      final enrolled = await create(enrollmentId: 'e1', storage: storage);

      final handed = await create(storage: storage, exactEnrollment: false);

      expect(identical(handed, enrolled), isTrue,
          reason: 'the fallback stays available to a caller that asks for '
              'it');
    });
  });
}
