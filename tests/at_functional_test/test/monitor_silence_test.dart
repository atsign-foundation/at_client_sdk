import 'package:at_client/at_client.dart';
import 'package:at_functional_test/src/config_util.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The socket-alive-but-silent watchdog, against a real atServer.
///
/// The atServer writes a stats notification to every monitor connection on its
/// own timer (15s by default), so a healthy monitor connection is never quiet
/// for long. That gives a real clock to bracket
/// [AtClientPreference.monitorSilenceTimeout] around, with no server
/// configuration and no test hook: a budget below the cadence makes a healthy
/// connection look silent and must rebuild, one above it must not.
///
/// The two arms differ only in that budget, and run for the same length of
/// time. They use different atSigns because [Monitor] holds the preference
/// OBJECT it was built with, so a second client for the same atSign would be
/// the same client, with the same budget.
///
/// What this cannot do is wedge a real atServer into answering heartbeats
/// while delivering nothing. It reproduces the condition the watchdog keys on
/// - nothing arrived inside the budget - which is the same code path.
void main() {
  TestUtils.isolateStorage('monitor_silence_test');

  /// Long enough to span two stats notifications either way.
  const window = Duration(seconds: 45);

  /// Counts `notConnected` -> `listening` cycles, which is what a rebuild
  /// looks like from outside: the public state stream, not a test seam.
  Future<int> rebuildsDuring(AtClient atClient, Duration forHowLong) async {
    var rebuilds = 0;
    var wasListening = false;
    // Registered before anything can happen: the stream is broadcast and does
    // not replay.
    final sub =
        atClient.notificationService.currentListenerStateStream.listen((state) {
      if (state == NotificationListenerState.listening) {
        if (wasListening) return;
        wasListening = true;
      } else {
        if (wasListening) rebuilds++;
        wasListening = false;
      }
    });
    atClient.notificationService.subscribe(regex: 'nothing.will.match');
    await Future.delayed(forHowLong);
    await sub.cancel();
    return rebuilds;
  }

  test('a budget under the atServer stats cadence rebuilds the connection',
      () async {
    final atSign = ConfigUtil.getYaml()['atSign']['firstAtSign'];
    final manager = await TestUtils.initAtClient(atSign, 'wavi',
        posture: PqPosture.legacy,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy)
          ..monitorSilenceTimeout = const Duration(seconds: 3));

    final rebuilds = await rebuildsDuring(manager.atClient, window);

    expect(rebuilds, greaterThan(0),
        reason: 'nothing arrived inside a 3-second budget on a connection the '
            'atServer never dropped, so the monitor tore it down and built a '
            'new one. at_lookup cannot do this: it sees a socket that is up '
            'and answering, and a client left on it reports listening while '
            'receiving nothing');
    expect(manager.atClient.notificationService.currentListenerState,
        NotificationListenerState.listening,
        reason: 'and the rebuild finished against the real atServer - a fresh '
            'TLS connection, authenticated, monitoring again - rather than '
            'leaving the client down');
  }, timeout: Timeout(Duration(minutes: 2)));

  test('a budget over it leaves the connection alone', () async {
    final atSign = ConfigUtil.getYaml()['atSign']['secondAtSign'];
    final manager = await TestUtils.initAtClient(atSign, 'wavi',
        posture: PqPosture.legacy,
        preference: TestUtils.getPreference(atSign, posture: PqPosture.legacy)
          ..monitorSilenceTimeout = const Duration(seconds: 40));

    final rebuilds = await rebuildsDuring(manager.atClient, window);

    // The premise first, so an atServer that has stopped sending stats fails
    // as itself rather than looking like a broken watchdog.
    expect(manager.atClient.notificationService.lastReceipt, isNotNull,
        reason: 'the atServer sends a stats notification to every monitor '
            'connection on its own timer, which is what makes silence a '
            'usable signal at all. Nothing arrived here, so the arm below '
            'would prove nothing');
    expect(rebuilds, 0,
        reason: 'those arrivals are inside a 40-second budget, so the check is '
            'about SILENCE rather than elapsed time - otherwise it would '
            'rebuild a perfectly good connection on a timer');
  }, timeout: Timeout(Duration(minutes: 2)));
}
