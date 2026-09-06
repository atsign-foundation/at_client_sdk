import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  late String firstAtSign;
  late String secondAtSign;
  final namespace = 'lifecycletest';

  setUpAll(() async {
    firstAtSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    secondAtSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
  });

  tearDown(() async {
    final activeInstances =
        List<AtClient>.from(AtClientImpl.atClientInstanceMap.values);
    for (var client in activeInstances) {
      await (client as AtClientImpl).stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
  });

  group('AtClient lifecycle tests', () {
    test('create, use, and stop AtClient successfully', () async {
      var atClientManager =
          await TestUtils.initAtClient(firstAtSign, namespace);
      var atClient = atClientManager.atClient;

      final phoneKey = AtKey()
        ..key = 'phone'
        ..sharedWith = secondAtSign;
      await atClient.put(phoneKey, '+1234567890');

      final AtValue result = await atClient.get(phoneKey);
      expect(result.value, '+1234567890');

      await (atClient as AtClientImpl).stop();
      expect(
        AtClientImpl.atClientInstanceMap.containsKey(firstAtSign),
        false,
        reason: 'a stopped client releases its storage and leaves the map',
      );
    });

    test('close() is idempotent and handles active operations', () async {
      var atClientManager =
          await TestUtils.initAtClient(secondAtSign, namespace);
      var atClient = atClientManager.atClient as AtClientImpl;

      await atClient.put(AtKey()..key = 'location', 'San Francisco');
      atClient.syncService.sync(); // Trigger sync

      // Close immediately while operations in process
      await atClient.stop();
      await atClient.stop();

      expect(AtClientImpl.atClientInstanceMap.containsKey(secondAtSign), false,
          reason: 'stop() is idempotent, and the first call already released');
    });

    test('stop with active notifications cleans up gracefully', () async {
      var atClientManager =
          await TestUtils.initAtClient(firstAtSign, namespace);
      var atClient = atClientManager.atClient;

      final receivedNotifications = <AtNotification>[];
      atClient.notificationService
          .subscribe(regex: '.$namespace')
          .listen(receivedNotifications.add);

      atClient.notificationService.notify(
        NotificationParams.forUpdate(
            AtKey()
              ..key = 'testnotif'
              ..sharedWith = firstAtSign,
            value: 'test value'),
      );

      await (atClient as AtClientImpl).stop();
    });
  });

  group('Implicit client caching behavior', () {
    test('switching atSigns stops and releases the outgoing client', () async {
      final atClient1 =
          (await TestUtils.initAtClient(firstAtSign, namespace)).atClient;
      var atKey = AtKey()
        ..key = 'alice_data'
        ..namespace = namespace;
      await atClient1.put(atKey, 'Alice value');

      final atClient2 =
          (await TestUtils.initAtClient(secondAtSign, namespace)).atClient;
      atKey = AtKey()..key = 'bob_data';
      await atClient2.put(atKey, 'Bob value');

      expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), false,
          reason: 'the outgoing client is stopped, and a stopped client leaves '
              'the map');
      expect(AtClientImpl.atClientInstanceMap.containsKey(secondAtSign), true);

      // Verify current atSign is correct
      expect(AtClientManager.getInstance().atClient.getCurrentAtSign(),
          equals(secondAtSign));

      // Verify operations work
      final verifyKey = AtKey()
        ..key = 'verify_read'
        ..namespace = namespace;
      await AtClientManager.getInstance().atClient.put(verifyKey, 'test');
      final result =
          await AtClientManager.getInstance().atClient.get(verifyKey);
      expect(result.value, 'test');

      await (atClient1 as AtClientImpl).stop();
      await (atClient2 as AtClientImpl).stop();
    });

    test('switching back builds a fresh client on the same store', () async {
      final atClient1 =
          (await TestUtils.initAtClient(firstAtSign, namespace)).atClient;
      final key = AtKey()
        ..key = 'alice_reuse'
        ..namespace = namespace;
      await atClient1.put(key, 'Alice value');

      await TestUtils.initAtClient(secondAtSign, namespace);
      final reusedAtClient =
          (await TestUtils.initAtClient(firstAtSign, namespace)).atClient;

      expect(identical(atClient1, reusedAtClient), false,
          reason: 'the first client released its storage when the manager '
              'switched away; the store itself persists, so the value below '
              'is still there');

      final AtValue result = await reusedAtClient.get(key);
      expect(result.value, 'Alice value');

      await (reusedAtClient as AtClientImpl).stop();
    });

    test('stop() on the outgoing client releases it from the cache', () async {
      final atClient1 = (await TestUtils.initAtClient(firstAtSign, namespace))
          .atClient as AtClientImpl;
      final atClientManager =
          await TestUtils.initAtClient(secondAtSign, namespace);

      expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), false);
      expect(atClient1.isStopped, true);

      await atClient1.stop();
      await (atClientManager.atClient as AtClientImpl).stop();
    });

    test('rapid switching leaves only the current client in the cache',
        () async {
      final atClientManager = AtClientManager.getInstance();
      final switchSequence = [
        firstAtSign,
        secondAtSign,
        firstAtSign,
        secondAtSign,
        firstAtSign,
        firstAtSign,
        firstAtSign,
        secondAtSign
      ];
      for (var atSignToSwitch in switchSequence) {
        await TestUtils.initAtClient(atSignToSwitch, namespace);
        await atClientManager.atClient.put(
            AtKey()
              ..key = 'rapid'
              ..namespace = namespace,
            'v');
      }

      expect(AtClientImpl.atClientInstanceMap.containsKey(firstAtSign), false,
          reason: 'every switch away released the outgoing client');
      expect(AtClientImpl.atClientInstanceMap.containsKey(secondAtSign), true);
      await (atClientManager.atClient as AtClientImpl).stop();
    });
  });
}
