// The PQ bootstrap is @experimental; this drives it.
// ignore_for_file: experimental_member_use

@Tags(['pq'])
library;

import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/at_server_features.dart';
import 'package:at_client/src/service/notification_service_impl.dart';
import 'package:at_functional_test/src/at_keys_initializer.dart'
    show AtEncryptionKeysLoader;
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// An ephemeral notification reaches its recipient, and no atServer keeps it
/// across a restart, while an ordinary one sent beside it survives.
void main() {
  TestUtils.isolateStorage('notification_lifetime_live_test');
  // NOTE: unique per run. A namespace key minted here takes a `_nskeylock`
  // whose ttl is a cooldown, so a fixed namespace fails on a second run.
  final runId = DateTime.now().microsecondsSinceEpoch;
  final namespace = 'lifetime$runId';
  late String alice;
  late String bob;
  final clients = <String, AtClient>{};

  Future<AtClient> open(String atSign) async {
    final loader = AtEncryptionKeysLoader.getInstance();
    final client = await Atsign(atSign).open(
        keys: InMemoryAtKeysIo.holding(
            atSign, loader.createAtKeysFromDemoKeys(atSign)),
        preference: TestUtils.getPreference(atSign,
            posture: PqPosture.pqActive)
          ..namespace = namespace,
        namespace: namespace,
        storage: TestUtils.storageFor(atSign));
    await loader.setEncryptionKeys(client, atSign);
    await (client as AtClientImpl).pqBootstrap!.startupComplete;
    return client;
  }

  setUpAll(() async {
    alice = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    bob = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    for (final atSign in [alice, bob]) {
      clients[atSign] = await open(atSign);
    }
    expect((await clients[bob]!.ensureReachable(namespace)).isReachable, isTrue,
        reason: '$bob must publish a namespace key before alice can share');
  });

  tearDownAll(() async {
    for (final client in clients.values) {
      await client.stop();
    }
  });

  test('an ephemeral notification is delivered and not kept across a restart',
      () async {
    if (!await AtServerFeatures.of(clients[alice]!).has('notify.eph')) {
      markTestSkipped('this atServer does not list notify.eph');
      return;
    }
    // NOTE: the rig names its compose file, which this test needs to restart
    // an atServer; without it there is no way to tell held from stored.
    final composeFile = Platform.environment['RIG_COMPOSE_FILE'];
    if (composeFile == null) {
      markTestSkipped('RIG_COMPOSE_FILE is not set');
      return;
    }
    final ephId = 'ephmsg$runId';
    final keepId = 'keepmsg$runId';

    final pending = {ephId: Completer<AtNotification>(), keepId: Completer()};
    final notifications =
        clients[bob]!.notificationService as NotificationServiceImpl;
    final subscription = notifications
        .subscribe(regex: namespace, shouldDecrypt: true)
        .listen((n) {
      for (final MapEntry(key: id, value: arrival) in pending.entries) {
        if (n.key.contains(id) && !arrival.isCompleted) arrival.complete(n);
      }
    });
    addTearDown(subscription.cancel);
    // NOTE: listener before trigger: a notification created before the
    // monitor listens is never delivered to it.
    await awaitMonitorListening(notifications,
        timeout: const Duration(seconds: 90));

    AtKey sentTo(String id) =>
        AtKey.fromString('$bob:$id.$namespace$alice')..namespace = namespace;
    final sentAt = DateTime.now();
    await clients[alice]!.notificationService.notify(
        NotificationParams.forUpdate(sentTo(ephId),
            value: 'gone after a restart', ephemeral: true));
    await clients[alice]!.notificationService.notify(
        NotificationParams.forUpdate(sentTo(keepId),
            value: 'still here after a restart'));
    expect(
        (await pending[ephId]!.future.timeout(const Duration(seconds: 60)))
            .value,
        'gone after a restart');
    expect(
        (await pending[keepId]!.future.timeout(const Duration(seconds: 60)))
            .value,
        'still here after a restart');

    Future<String> listed() async {
      for (var attempt = 1;; attempt++) {
        try {
          final response = await clients[bob]!
              .getRemoteSecondary()!
              .executeCommand('notify:list:$namespace\n', auth: true);
          if (response != null && response.startsWith('data:')) {
            return response;
          }
        } catch (e) {
          if (attempt >= 30) rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    expect(await listed(), allOf(contains(ephId), contains(keepId)),
        reason: 'the control: listing sees an ephemeral notification while it '
            'is held, so its absence below is the restart and not the listing');

    final status = await Process.run('docker', [
      'compose', '-f', composeFile, 'exec', '-T', 'virtualenv', //
      'supervisorctl', 'status'
    ]);
    final program = (status.stdout as String)
        .split('\n')
        .firstWhere((line) => line.contains('_$bob '))
        .split(RegExp(r'\s+'))
        .first;
    final restart = await Process.run('docker', [
      'compose', '-f', composeFile, 'exec', '-T', 'virtualenv', //
      'supervisorctl', 'restart', program
    ]);
    expect(restart.exitCode, 0, reason: '${restart.stdout}${restart.stderr}');

    final after = await listed();
    expect(DateTime.now().difference(sentAt),
        lessThan(ephemeralNotificationMaxLifetime),
        reason: 'inside its two minutes, so an absence is the restart and not '
            'its expiry');
    expect(after, contains(keepId),
        reason: 'an ordinary notification survives the restart');
    expect(after, isNot(contains(ephId)),
        reason: 'an ephemeral one was never stored');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
