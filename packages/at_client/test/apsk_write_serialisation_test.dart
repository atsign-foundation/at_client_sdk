import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/mixins/apkam_signing.dart'
    show serialiseApskWrite;
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

/// `_apsk` writes made by one process for one client are serialised.
///
/// A minter publishes its new signing key before it files it, so that no
/// envelope is ever signed under a key the advertisement does not name. In the
/// gap the keyfile does not hold what was advertised, so any other writer
/// composing from the keyfile sees no signing key, takes the
/// authentication-key fallback, and publishes that over the advertisement.
/// Measured live: the approver's own envelope signer overwrote its own mint
/// 20ms later, and the enrollment being approved then failed outright.
void main() {
  /// Records enter/exit order so an interleave is visible rather than inferred.
  late List<String> log;

  Future<void> section(AtClient client, String name, Duration hold) =>
      serialiseApskWrite(client, () async {
        log.add('$name:enter');
        await Future<void>.delayed(hold);
        log.add('$name:exit');
      });

  setUp(() => log = []);

  test('a second write waits for the first to finish', () async {
    final client = MockAtClient();

    // The slow one starts first and is still inside its section when the fast
    // one is requested — which is exactly the live shape: the mint publishes,
    // then files, and the envelope signer arrives in between.
    final slow = section(client, 'mint', const Duration(milliseconds: 60));
    final fast = section(client, 'signer', Duration.zero);
    await Future.wait([slow, fast]);

    expect(log, ['mint:enter', 'mint:exit', 'signer:enter', 'signer:exit'],
        reason: 'without the lock this is mint:enter, signer:enter, '
            'signer:exit, mint:exit — the signer composing and publishing '
            'inside the window the mint has not closed');
  });

  test('two clients are not serialised against each other', () async {
    final one = MockAtClient();
    final two = MockAtClient();

    final slow = section(one, 'one', const Duration(milliseconds: 60));
    final fast = section(two, 'two', Duration.zero);
    await Future.wait([slow, fast]);

    expect(log.indexOf('two:exit'), lessThan(log.indexOf('one:exit')),
        reason: 'two clients of one atSign are two enrollments writing two '
            'different records, so making one wait for the other would be a '
            'cost with nothing bought — and the control that shows the test '
            'above is measuring the lock rather than the delays');
  });

  test('a failed write does not wedge the chain', () async {
    final client = MockAtClient();

    final failing = serialiseApskWrite(client, () async {
      log.add('first:enter');
      throw StateError('the keyfile is unreadable');
    });
    await expectLater(failing, throwsStateError,
        reason: 'the error belongs to the caller that caused it');

    await section(client, 'second', Duration.zero);
    expect(log, ['first:enter', 'second:enter', 'second:exit'],
        reason: 'a predecessor that threw must not leave every later write '
            'waiting on a chain entry that will never complete — an _apsk '
            'that stops being publishable is a client whose envelopes stop '
            'verifying');
  });

  test('a write queued behind a failure still runs', () async {
    final client = MockAtClient();

    // Queued while the failing one is in flight, not after it: this is the
    // arm that fails if the chain propagates the error instead of swallowing
    // it at the join.
    final failing = serialiseApskWrite(client, () async {
      log.add('first:enter');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      throw StateError('the keyfile is unreadable');
    });
    final queued = section(client, 'second', Duration.zero);

    await expectLater(failing, throwsStateError);
    await queued;
    expect(log, ['first:enter', 'second:enter', 'second:exit']);
  });

  test('the section is entered once per call, in call order', () async {
    final client = MockAtClient();

    await Future.wait([
      for (var i = 0; i < 5; i++)
        section(client, '$i', Duration(milliseconds: 5 * (5 - i)))
    ]);

    expect(log, [
      for (var i = 0; i < 5; i++) ...['$i:enter', '$i:exit']
    ], reason: 'later callers queue in the order they asked, and no section '
        'overlaps another — the delays descend so an unlocked implementation '
        'would finish them in the opposite order');
  });
}
