@TestOn('browser')
library;

import 'dart:async';

import 'package:at_client_wasm/src/session/web_setup_lock.dart';
import 'package:test/test.dart';

void main() {
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
    final result =
        await WebSetupLock(acquireTimeout: const Duration(milliseconds: 50))
            .run(name, () async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return 'done';
    });
    expect(result, 'done');
  });
}
