import 'dart:async';

import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:at_client_web/src/session/session_queue.dart';
import 'package:test/test.dart';

void main() {
  test('a saturated open queue rejects the next open, which maps to internal',
      () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final lock = openLock('@queue-test', 'eid1');

    final held = queuedOpen<void>(lock, () {
      started.complete();
      return release.future;
    });
    await started.future;

    // The page-wide queue caps waiters per lock at 16.
    final queued = [
      for (var i = 0; i < 16; i++) queuedOpen<void>(lock, () async {})
    ];

    Object? error;
    try {
      await queuedOpen<void>(lock, () async {});
    } catch (e) {
      error = e;
    }

    expect(error, isA<QueueLimitException>());
    expect(errorCodeOf(error!), 'internal');

    release.complete();
    await held;
    await Future.wait(queued);
  });
}
