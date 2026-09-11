import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookupImpl extends Mock implements AtLookupImpl {}

class MockAtAuthImpl extends Mock implements AtAuth {}

class FakeAtAuthRequest extends Fake implements AtAuthRequest {}

/// Records the storage the manager passes on to the client factory.
class RecordingServiceFactory extends DefaultAtServiceFactory {
  AtClientStorage? seen;
  bool called = false;

  @override
  Future<AtClient> atClient(String atSign, String? namespace,
      AtClientPreference preference, AtClientManager atClientManager,
      {AtChops? atChops,
      AtKeysIo? atKeysIo,
      AtLookUp? atLookUp,
      String? enrollmentId,
      AtClientStorage? storage}) async {
    called = true;
    seen = storage;
    return super.atClient(atSign, namespace, preference, atClientManager,
        atKeysIo: atKeysIo,
        atLookUp: atLookUp,
        enrollmentId: enrollmentId,
        storage: storage);
  }
}

void main() {
  AtSignLogger.root_level = 'SHOUT';
  final atSign = '@alice🛠';
  late Directory dir;
  final mockAtLookup = MockAtLookupImpl();
  final mockAtAuth = MockAtAuthImpl();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('onboarding_storage_');
    reset(mockAtLookup);
    when(() => mockAtLookup.close()).thenAnswer(Future.value);
    reset(mockAtAuth);
    registerFallbackValue(FakeAtAuthRequest());
    when(() => mockAtAuth.progressStream).thenAnswer((_) => Stream.empty());
    AtClientManager.getInstance().reset();
  });

  tearDown(() async {
    for (final c
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await c.stop();
    }
    AtClientManager.getInstance().reset();
    dir.deleteSync(recursive: true);
  });

  Future<AtOnboardingServiceImpl> authenticated(
      AtOnboardingPreference preference, AtServiceFactory factory) async {
    final service =
        AtOnboardingServiceImpl(atSign, preference, atServiceFactory: factory);
    service.atLookUp = mockAtLookup;
    service.atAuth = mockAtAuth;
    when(() => mockAtLookup.pkamAuthenticate())
        .thenAnswer((_) => Future.value(true));
    when(() => mockAtAuth.authenticate(any()))
        .thenAnswer((_) => Future.value(AtAuthResponse(atSign)
          ..isSuccessful = true
          ..atAuthKeys = (AtKeys()
            ..apkamPublicKey = AtBytes.fromString('dumm')
            ..apkamPrivateKey = AtBytes.fromString('dumm')
            ..defaultSelfEncryptionKey = AtBytes.fromString('dumm')
            ..defaultEncryptionPrivateKey = AtBytes.fromString('dumm')
            ..defaultEncryptionPublicKey = AtBytes.fromString('dumm')
            ..apkamSymmetricKey = AtBytes.fromString('dumm')
            ..enrollmentId = 'dummy_enroll_id')));

    expect(await service.authenticate(), isTrue);
    return service;
  }

  test('the storage on the preference is the one the client holds', () async {
    final storage = HiveAtClientStorage(atSign: atSign, storagePath: dir.path);
    final factory = RecordingServiceFactory();
    final service = await authenticated(
        AtOnboardingPreference()
          ..atKeysFilePath = 'test/data/${atSign}_key.atKeys'
          ..namespace = 'unit_test'
          ..storagePath = '${dir.path}/never_opened'
          ..storage = storage,
        factory);

    expect(factory.seen, same(storage),
        reason: 'the bundle put on the preference is the one that reached the '
            'client factory, rather than being dropped on the way');
    expect(storage.isHeldBy(service.atClient!), isTrue,
        reason: 'and the client opened THAT bundle, rather than a Hive store '
            'under hiveStoragePath');
    expect(Directory('${dir.path}/never_opened').existsSync(), isFalse,
        reason: 'storagePath goes unread when a bundle is supplied');

    await service.atClient!.stop();
    await storage.close();
  });

  test('no bundle on the preference gets a client-closed one at storagePath',
      () async {
    final factory = RecordingServiceFactory();
    final service = await authenticated(
        AtOnboardingPreference()
          ..atKeysFilePath = 'test/data/${atSign}_key.atKeys'
          ..namespace = 'unit_test'
          ..storagePath = '${dir.path}/built_for_the_cli',
        factory);

    expect(factory.seen, isA<HiveAtClientStorage>(),
        reason: 'the CLI supplies a bundle of its own rather than leaving '
            'at_client to open one from a preference path');
    expect(factory.seen!.closedByClient, isTrue,
        reason: 'and the client is what closes it, so a CLI still has nothing '
            'to tear down');
    expect(Directory('${dir.path}/built_for_the_cli').existsSync(), isTrue,
        reason: 'the store landed where storagePath said');

    await service.atClient!.stop();
  });

  test('the deprecated hiveStoragePath still decides where the store goes',
      () async {
    final factory = RecordingServiceFactory();
    final service = await authenticated(
        AtOnboardingPreference()
          ..atKeysFilePath = 'test/data/${atSign}_key.atKeys'
          ..namespace = 'unit_test'
          // ignore: deprecated_member_use
          ..hiveStoragePath = '${dir.path}/legacy_path',
        factory);

    expect(Directory('${dir.path}/legacy_path').existsSync(), isTrue,
        reason: 'a caller that set the deprecated field before this change '
            'keeps the location it had');
    expect(factory.seen!.closedByClient, isTrue);

    await service.atClient!.stop();
  });
}
