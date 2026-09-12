import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

import 'lifecycle_rig.dart';

/// Where the client `authenticate()` opens keeps its local storage: the
/// store on the preference when there is one, else a Hive store under the
/// preference's path that the client closes itself.
void main() {
  AtSignLogger.root_level = 'SHOUT';
  const atSign = '@alice🛠';
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('onboarding_storage_');
    AtClientManager.getInstance().reset();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  Future<AtOnboardingPreference> preference() async =>
      AtOnboardingPreference(posture: PqPosture.legacy)
        ..atKeysFilePath = 'test/data/${atSign}_key.atKeys'
        ..namespace = 'unit_test'
        ..rootDomain = InternetAddress.loopbackIPv4.address
        ..rootPort = await refusedPort();

  Future<AtOnboardingServiceImpl> authenticated(
      AtOnboardingPreference preference) async {
    final service = AtOnboardingServiceImpl(atSign, preference,
        atLookUp: lookUpAnswering(() async => true));
    expect(await service.authenticate(), isTrue);
    return service;
  }

  test('the storage on the preference is the one the client holds', () async {
    final storage = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    final service = await authenticated((await preference())
      ..storagePath = '${dir.path}/never_opened'
      ..storage = storage);

    expect(storage.isHeldBy(service.atClient!), isTrue,
        reason: 'the client opened THAT bundle, rather than a Hive store '
            'under storagePath');
    expect(Directory('${dir.path}/never_opened').existsSync(), isFalse,
        reason: 'storagePath goes unread when a bundle is supplied');

    await service.atClient!.stop();
    await storage.close();
  });

  test('no bundle on the preference gets a client-closed one at storagePath',
      () async {
    final pref = (await preference())
      ..storagePath = '${dir.path}/built_for_the_cli';
    final service = await authenticated(pref);

    expect(Directory('${dir.path}/built_for_the_cli').existsSync(), isTrue,
        reason: 'the store landed where storagePath said');
    expect(pref.storageFor(atSign).closedByClient, isTrue,
        reason: 'and the client is what closes it, so a CLI still has nothing '
            'to tear down');

    await service.atClient!.stop();
  });

  test('the deprecated hiveStoragePath still decides where the store goes',
      () async {
    final service = await authenticated((await preference())
      // ignore: deprecated_member_use
      ..hiveStoragePath = '${dir.path}/legacy_path');

    expect(Directory('${dir.path}/legacy_path').existsSync(), isTrue,
        reason: 'a caller that set the deprecated field keeps the location '
            'it had');

    await service.atClient!.stop();
  });
}
