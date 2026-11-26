import 'dart:async';

import 'package:at_client_web/src/exceptions.dart';
import 'package:at_client_web/src/js/error_codes.dart';
import 'package:at_client_web/src/session/session_queue.dart';
import 'package:test/test.dart';

void main() {
  test(
      'a saturated open queue rejects the next open, which maps to invalid_argument',
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
    // D-43: `internal` is for a Dart Error or an unexpected type only, and
    // `invalid_argument` absorbs what it used to answer for a caller's own
    // excess; a caller with sixteen opens waiting on one lock is looping.
    expect(errorCodeOf(error!), 'invalid_argument');
    expect(
        atErrorMessage(error),
        'too many opens are already waiting for '
        'this atSign');

    release.complete();
    await held;
    await Future.wait(queued);
  });
}
