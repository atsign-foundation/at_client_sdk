import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_persistence_secondary_server/hive.dart';
import 'package:hive/hive.dart';
import 'package:test/test.dart';

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
    ..hiveStoragePath = dir.path
    ..commitLogPath = '${dir.path}/commit';

  AtBytes b64(String s) => AtBytes.fromString(base64Encode(utf8.encode(s)));

  Future<InMemoryAtKeysIo> keyfile({String? flatEnrollmentId}) async {
    final io = InMemoryAtKeysIo();
    await io.write(
        atSign,
        AtKeys()
          ..apkamPublicKey = b64('apkam-public')
          ..apkamPrivateKey = b64('apkam-private')
          ..defaultEncryptionPublicKey = b64('enc-public')
          ..defaultEncryptionPrivateKey = b64('enc-private')
          ..defaultSelfEncryptionKey = b64('self-key')
          // ignore: deprecated_member_use
          ..enrollmentId = flatEnrollmentId);
    return io;
  }

  test('a legacy keyfile runs the client as its flat stored enrollment',
      () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        atKeysIo: await keyfile(flatEnrollmentId: 'stored-1'));
    expect(client.enrollmentId, 'stored-1');
  });

  test('a disagreeing id is ignored and the keys win', () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        atKeysIo: await keyfile(flatEnrollmentId: 'stored-1'),
        enrollmentId: 'somebody-else');
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
        atChops: AtChopsImpl(AtChopsKeys()),
        atKeysIo: io,
        enrollmentId: 'apkam-1');
    expect(client.enrollmentId, 'apkam-1',
        reason: 'no material, so nothing to derive from; the caller\'s id '
            'is the credential\'s');
  });

  test('a keyfile that predates enrollments runs the client as primary',
      () async {
    final client = await AtClientImpl.create(atSign, 'wavi', pref(),
        atKeysIo: await keyfile());
    expect(client.enrollmentId, 'primary');
  });
}
