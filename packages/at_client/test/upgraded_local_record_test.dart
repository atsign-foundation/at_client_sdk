// The bridge that builds a client's AtChops from a keyfile insists on a
// credential, so this fixture hands the client a placeholder signer; nothing
// here signs, and the key source carries the material that is read.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/manager/monitor.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_persistence_secondary_server/at_persistence_secondary_server.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/ml_dsa_keyfile.dart';
import 'test_utils/mocks.dart';
import 'test_utils/no_op_services.dart';
import 'test_utils/recorded_logs.dart';

class _FakeMonitor extends Fake implements Monitor {
  @override
  NotificationListenerState currentState =
      NotificationListenerState.notConnected;

  @override
  NotificationListenerState targetState =
      NotificationListenerState.notConnected;

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}
}

/// A store written by at_client 3.14.0 or earlier holds every `local:` record
/// encrypted under the self key and flagged `isEncrypted: true`; `local:`
/// records are now stored as given. These tests seed the keystore the way each
/// of those clients left it and drive the production pipeline over it.
void main() {
  const atSign = '@alice';
  const namespace = 'upgrade';
  const cursorName = 'lastreceivedservercommitid';
  const cursor = 'local:$cursorName.$namespace$atSign';
  const skipDeletes = 'local:skipdeletesuntil.$namespace$atSign';
  const watermark = 'local:lastreceivednotification.$namespace$atSign';

  late Directory dir;
  late AtClientImpl atClient;
  late AtKeyValueStore<String, AtData, AtMetaData?> store;
  final selfEncryptionKey = EncryptionUtil.generateAESKey();
  final logs = RecordedLogs();

  /// What a 3.14.0 put stored for a non-public record: the self-key
  /// ciphertext, flagged encrypted and stamped with the legacy provider.
  Future<void> seedAsEncrypted(String key, String plaintext) async {
    final iv = EncryptionUtil.generateIV();
    await store.putAll(
        key,
        AtData()
          ..data = EncryptionUtil.encryptValue(plaintext, selfEncryptionKey,
              ivBase64: iv),
        AtMetaData.fromCommonsMetadata(
            Metadata()
              ..isEncrypted = true
              ..ivNonce = iv
              ..appMetadata = AppMetadata(providerId: legacyCryptoProviderId),
            atSign));
  }

  /// What a 3.15.0 prerelease left after reading a 3.14.0 record and writing
  /// back through the same `AtKey`: the plain value under the old flags.
  /// [stamped] false is a record from a client old enough to write no
  /// provider id; [encoded] is a value stored base64-encoded, as one with a
  /// newline is.
  Future<void> seedAsMislabelled(String key, String plaintext,
      {bool stamped = true, bool encoded = false}) async {
    await store.putAll(
        key,
        AtData()
          ..data = encoded ? base64Encode(utf8.encode(plaintext)) : plaintext,
        AtMetaData.fromCommonsMetadata(
            Metadata()
              ..isEncrypted = true
              ..ivNonce = EncryptionUtil.generateIV()
              ..encoding = encoded ? 'base64' : null
              ..appMetadata = stamped
                  ? AppMetadata(providerId: legacyCryptoProviderId)
                  : null,
            atSign));
  }

  Future<AtData> stored(String key) async => (await store.get(key))!;

  setUpAll(() async {
    logs.installOn();
    dir = Directory.systemTemp.createTempSync('upgraded_local_record_');
    atClient = (await AtClientImpl.create(
        atSign,
        namespace,
        AtClientPreference()
          ..namespace = namespace
          ..hiveStoragePath = dir.path
          ..commitLogPath = dir.path,
        remoteSecondary: MockRemoteSecondary(),
        atChops: AtChopsImpl(AtChopsKeys.create(null, null)),
        atKeysIo: await keyfileHolding(atSign,
            selfEncryptionKey: selfEncryptionKey))) as AtClientImpl;
    atClient.syncService = NoOpSyncService();
    store = atClient.getLocalSecondary()!.keyStore!;
    await atClient
        .getLocalSecondary()!
        .putValue(AtConstants.atEncryptionSelfKey, selfEncryptionKey);
  });

  tearDownAll(() async {
    await atClient.stop();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    for (final key in [cursor, skipDeletes, watermark]) {
      if (await store.exists(key)) await store.remove(key);
    }
  });

  group('a record 3.14.0 encrypted', () {
    test('is decrypted', () async {
      await seedAsEncrypted(cursor, '593639');

      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          '593639',
          reason: 'the positive control: the fixture is real self-key '
              'ciphertext, which the read path still opens');
    });

    test('reads back after a write through the AtKey that read it', () async {
      await seedAsEncrypted(cursor, '593639');
      final key = AtKey.local(cursorName, atSign).build();

      await atClient.get(key);
      expect(key.metadata.isEncrypted, isTrue,
          reason: 'the premise: the read leaves the stored flag on the key');
      await atClient.put(key, '593700');

      expect((await stored(cursor)).metaData!.isEncrypted, isFalse,
          reason: 'the value is stored as given, so the flag must say so, or '
              'every later read tries to decrypt a plain value');
      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          '593700');
    });

    test('reads back after a write without encryption through that AtKey',
        () async {
      await seedAsEncrypted(cursor, '593639');
      final key = AtKey.local(cursorName, atSign).build();

      await atClient.get(key);
      await atClient.put(key, '593700',
          putRequestOptions: PutRequestOptions()..shouldEncrypt = false);

      expect((await stored(cursor)).metaData!.isEncrypted, isFalse,
          reason: 'the SDK never encrypts a local value, so opting out of '
              'encryption cannot leave one sealed');
      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          '593700');
    });
  });

  test('a value written back over a multi-line one reads back', () async {
    final key = AtKey.local('multiline', atSign).build();
    await atClient.put(key, 'line one\nline two');
    await atClient.get(key);
    expect(key.metadata.encoding, isNotNull,
        reason: 'the premise: the read leaves the stored encoding on the key');

    await atClient.put(key, 'one line');

    expect((await atClient.get(AtKey.local('multiline', atSign).build())).value,
        'one line',
        reason: 'a value stored as given carries no encoding, or the read '
            'decodes plain text');
    await store.remove('local:multiline.$namespace$atSign');
  });

  group('a plain record flagged encrypted', () {
    test('is returned as stored', () async {
      await seedAsMislabelled(cursor, '593639');

      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          '593639',
          reason: 'a value that cannot be self-key ciphertext is the plain '
              'value a 3.15.0 prerelease wrote; refusing it stops sync for '
              'good on that device');
    });

    test('is returned as stored when it is JSON', () async {
      final json = jsonEncode({'id': 'n1', 'epochMillis': 1759000000000});
      await seedAsMislabelled(watermark, json);

      expect(
          (await atClient.get(AtKey.local('lastreceivednotification', atSign,
                      namespace: namespace)
                  .build()))
              .value,
          json);
    });

    test('is returned as stored when it is encoded', () async {
      // Sixteen bytes, so its base64 is shaped like legacy ciphertext.
      const lines = 'sixteen chars\nXY';
      await seedAsMislabelled(cursor, lines, encoded: true);

      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          lines,
          reason: 'the SDK never encodes a value it encrypts, so an encoded '
              'value is a plain one, whatever its length');
    });

    test('is returned as stored when it carries no provider id', () async {
      await seedAsMislabelled(cursor, '593639', stamped: false);

      expect(
          (await atClient.get(AtKey.local(cursorName, atSign).build())).value,
          '593639',
          reason: 'a client before provider ids existed wrote no stamp, and '
              'its legacy records route the same way');
    });

    test('is refused when the record is not local', () async {
      const selfKey = 'phone.$namespace$atSign';
      await seedAsMislabelled(selfKey, '593639');

      await expectLater(
          atClient.get(
              AtKey.self('phone', namespace: namespace, sharedBy: atSign)
                  .build()),
          throwsA(isA<FormatException>()),
          reason: 'only local records were ever written plain under a stale '
              'flag; a synced record carries the flag its writer set, so it '
              'is decrypted, and plain digits are not base64');
      await store.remove(selfKey);
    });
  });

  group('the sync cursors', () {
    late SyncServiceImpl syncService;

    setUp(() async {
      atClient.notificationService = await NotificationServiceImpl.create(
          atClient,
          monitor: _FakeMonitor());
      syncService = await SyncServiceImpl.create(atClient,
          remoteSecondary: MockRemoteSecondary(),
          warmStartSync: false) as SyncServiceImpl;
    });

    tearDown(() async => syncService.stop());

    test('the pull cursor advances from a 3.14.0 store', () async {
      await seedAsEncrypted(cursor, '593639');

      expect(await syncService.getLastReceivedServerCommitId(), 593639);
      await syncService.persistPullCursor(593700);

      expect((await stored(cursor)).metaData!.isEncrypted, isFalse,
          reason: 'the cursor is written plain, so its flag must say so');
      expect(await syncService.getLastReceivedServerCommitId(), 593700,
          reason: 'the second round is the one that stopped sync');
    });

    test('the pull cursor is read from a store a prerelease left', () async {
      await seedAsMislabelled(cursor, '593639');

      expect(await syncService.getLastReceivedServerCommitId(), 593639);
      await syncService.persistPullCursor(593700);

      expect((await stored(cursor)).metaData!.isEncrypted, isFalse,
          reason: 'the next write repairs the record');
      expect(await syncService.getLastReceivedServerCommitId(), 593700);
    });

    test('skipDeletesUntil is read from either store', () async {
      await seedAsEncrypted(skipDeletes, '575300');
      expect(
          await syncService.setAndGetSkipDeletesUntil(593639, 593700), 575300);

      await seedAsMislabelled(skipDeletes, '575300');
      expect(
          await syncService.setAndGetSkipDeletesUntil(593639, 593700), 575300);
    });
  });

  group('the notification watermark', () {
    late NotificationServiceImpl service;

    String receipt(String id, int epochMillis) => 'notification: '
        '{"id":"$id","from":"@bob","to":"$atSign","key":"$id.wavi$atSign",'
        '"value":null,"operation":"update","epochMillis":$epochMillis,'
        '"messageType":"MessageType.key","isEncrypted":false}';

    setUp(() async {
      service = await NotificationServiceImpl.create(atClient,
          monitor: _FakeMonitor()) as NotificationServiceImpl;
      atClient.notificationService = service;
    });

    test('advances from a 3.14.0 store', () async {
      await seedAsEncrypted(
          watermark, jsonEncode({'id': 'n0', 'epochMillis': 1759000000000}));

      expect(await service.getLastNotificationTime(), 1759000000000);
      await service.handleNotificationReceipt(receipt('n1', 1759000000500));

      expect((await stored(watermark)).metaData!.isEncrypted, isFalse,
          reason: 'the watermark is written plain, so its flag must say so');
      expect(await service.getLastNotificationTime(), 1759000000500,
          reason: 'a failed read here is taken as "no watermark", which '
              'resumes from now and skips everything sent while offline');
    });

    test('is read from a store a prerelease left', () async {
      await seedAsMislabelled(
          watermark, jsonEncode({'id': 'n0', 'epochMillis': 1759000000000}));

      expect(await service.getLastNotificationTime(), 1759000000000,
          reason: 'not the time this service was created');
    });

    test('a read that fails is logged at warning', () async {
      await store.putAll(
          watermark,
          AtData()..data = jsonEncode({'id': 'n0', 'epochMillis': 1}),
          AtMetaData.fromCommonsMetadata(
              Metadata()
                ..isEncrypted = true
                ..appMetadata = AppMetadata(providerId: 'unregistered'),
              atSign));

      await service.getLastNotificationTime();

      expect(logs.at('WARNING'), contains(contains(watermark)),
          reason: 'the monitor then resumes from now and skips everything '
              'sent while offline; silence reads as nothing having been sent');
    });
  });
}
