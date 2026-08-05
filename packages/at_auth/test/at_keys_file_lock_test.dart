import 'dart:io';

import 'package:at_auth/src/keys/io/file_lock.dart';
import 'package:test/test.dart';

/// The keyfile's inter-process advisory lock.
///
/// The failure it exists for: two processes sharing one `.atKeys` both read
/// before either writes; both pass `validateMapUpdate` (each candidate
/// preserves what *it* read); the second rename silently discards the first's
/// addition — a conveyed nskey private that appears filed and is not.
void main() {
  late Directory dir;
  late String protected;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('atkeys_lock_test');
    protected = '${dir.path}/@alice_key.atKeys';
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('two contenders serialise: interleaving is impossible under the lock',
      () async {
    final lock1 = AtKeysFileLock(protected);
    final lock2 = AtKeysFileLock(protected);
    final events = <String>[];

    // Both start together. Without the lock the enters interleave —
    // enter/enter/exit/exit — which is exactly the read-before-write overlap
    // that loses an addition.
    await Future.wait([
      lock1.synchronized(() async {
        events.add('a-enter');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        events.add('a-exit');
      }),
      lock2.synchronized(() async {
        events.add('b-enter');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        events.add('b-exit');
      }),
    ]);

    expect(events, hasLength(4));
    // Whichever won, its exit precedes the other's enter.
    final first = events.first.split('-').first;
    expect(events.sublist(0, 2), ['$first-enter', '$first-exit'],
        reason: 'the critical sections must not interleave — an interleaved '
            'order here is the lost-addition race, reproduced');
  });

  test('the lock is released on an action that throws', () async {
    final lock = AtKeysFileLock(protected);

    await expectLater(
        () => lock.synchronized(() async => throw StateError('boom')),
        throwsA(isA<StateError>()));

    // A second acquisition must succeed promptly — a lock leaked on the error
    // path turns one failed flush into every later flush timing out.
    var ran = false;
    await AtKeysFileLock(protected, timeout: const Duration(seconds: 1))
        .synchronized(() async => ran = true);
    expect(ran, isTrue);
  });

  test('a stale lock is broken rather than waited on forever', () async {
    // A crashed process's leftover: present, and old.
    final leftover = File('$protected.lock');
    await leftover.create(recursive: true);
    await leftover
        .setLastModified(DateTime.now().subtract(const Duration(minutes: 5)));

    var ran = false;
    await AtKeysFileLock(protected,
            timeout: const Duration(seconds: 2),
            staleAfter: const Duration(seconds: 30))
        .synchronized(() async => ran = true);

    expect(ran, isTrue,
        reason: 'a process that crashed holding the lock must not deadlock '
            'every future run of every app sharing the keyfile');
  });

  test(
      'a fresh lock held by a live process is waited on, then times out '
      'loudly', () async {
    await File('$protected.lock').create(recursive: true);

    await expectLater(
        () => AtKeysFileLock(protected,
                timeout: const Duration(milliseconds: 300),
                staleAfter: const Duration(minutes: 5))
            .synchronized(() async {}),
        throwsA(isA<FileSystemException>()),
        reason: 'an unbreakable silent wait inside key-material code turns a '
            'stuck sibling into a hung app with no diagnosis — the timeout '
            'must name the lock');
  });
}
