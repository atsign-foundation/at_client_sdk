@TestOn('browser')
library;

import 'dart:async';

import 'package:at_auth/passkey.dart' show setupLockName;
import 'package:at_client_web/src/session/web_setup_lock.dart';
import 'package:test/test.dart';

void main() {
  test('the wasm lock name is the pinned string', () {
    expect(setupLockName(WebSetupLock.namePrefix, '@alice'),
        'at_client_web:setup:@alice');
  });

  test('a waiter times out while the lock is held, then succeeds after',
      () async {
    final name = 'lock_${DateTime.now().microsecondsSinceEpoch}';
    final entered = Completer<void>();
    final release = Completer<void>();
    final holder = WebSetupLock().run(name, () async {
      entered.complete();
      await release.future;
    });
    await entered.future;

    await expectLater(
      WebSetupLock(acquireTimeout: const Duration(milliseconds: 100))
          .run(name, () async => 1),
      throwsA(isA<SetupLockTimeoutException>()
          .having((e) => e.lockName, 'lockName', name)),
    );

    release.complete();
    await holder;
    expect(await WebSetupLock().run(name, () async => 2), 2);
  });

  test('the timeout does not bound the held section', () async {
    final name = 'lock_${DateTime.now().microsecondsSinceEpoch}';
    const timeout = Duration(milliseconds: 50);
    final result =
        await WebSetupLock(acquireTimeout: timeout).run(name, () async {
      // The wait must outlast the acquire timeout to prove the timeout
      // does not bound the body.
      await Future<void>.delayed(timeout * 4);
      return 'done';
    });
    expect(result, 'done');
  });

  test('a body that throws gives the caller that error and nothing uncaught',
      () async {
    final name = 'lock_${DateTime.now().microsecondsSinceEpoch}';
    final uncaught = <Object>[];
    Object? caught;
    await runZonedGuarded(() async {
      try {
        await WebSetupLock().run(name, () async => throw FormatException('x'));
      } on Object catch (e) {
        caught = e;
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }, (e, s) => uncaught.add(e));

    expect(caught, isA<FormatException>());
    expect(uncaught, isEmpty);
  });
}
