import 'package:at_client/at_client.dart';
import 'package:test/test.dart';

void main() {
  group('setCurrentAtSign after stop()', () {
    AtClientPreference pref() => AtClientPreference()
      ..hiveStoragePath = 'test/hive'
      ..commitLogPath = 'test/hive/path';

    test(
        'the same-atSign short-circuit never hands back a stopped client, and '
        'the client it does hand back has its services wired', () async {
      final atSign = '@stoppedshortcircuit';
      final manager = AtClientManager(atSign);
      await manager.setCurrentAtSign(atSign, 'wavi', pref());
      final first = manager.atClient;
      await first.stop();
      expect(first.isStopped, isTrue);

      await manager.setCurrentAtSign(atSign, 'wavi', pref());
      final again = manager.atClient;
      expect(again.isStopped, isFalse,
          reason: 'setCurrentAtSign must not return a client that is still '
              'stopped; the short-circuit has to fall through for one');
      expect(() => again.syncService, returnsNormally,
          reason: 'stop() nulls the services, so whatever hands the client '
              'back must have wired them again');
      expect(() => again.notificationService, returnsNormally,
          reason: 'as for syncService');
    });
  });
}
