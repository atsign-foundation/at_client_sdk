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

  test("release leaves a lock that is no longer the holder's own", () async {
    // While A holds, a stale-breaker (from A's point of view: A stalled past
    // staleAfter) breaks the lock and B acquires. A's release must not evict B.
    final lockFile = File('$protected.lock');
    await AtKeysFileLock(protected).synchronized(() async {
      // Simulate the break plus B's acquisition by replacing the content.
      await lockFile.writeAsString('another-holder\n');
    });

    expect(lockFile.existsSync(), isTrue,
        reason: "a holder whose lock was broken while it ran must not delete "
            "the new holder's lock on exit — that eviction lets a third "
            'contender into the critical section alongside the new holder');
    expect(await lockFile.readAsString(), 'another-holder\n');
  });

  test('breaking a stale lock leaves no rename residue beside the keyfile',
      () async {
    final leftover = File('$protected.lock');
    await leftover.create(recursive: true);
    await leftover
        .setLastModified(DateTime.now().subtract(const Duration(minutes: 5)));

    await AtKeysFileLock(protected, timeout: const Duration(seconds: 2))
        .synchronized(() async {});

    final residue = dir
        .listSync()
        .map((e) => e.path)
        .where((p) => p.contains('.breaking.'))
        .toList();
    expect(residue, isEmpty,
        reason: 'the break claims the corpse by rename and must delete the '
            'claimed file, not accumulate siblings beside the keyfile');
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

  test('a create that fails for a reason contention cannot fix still times out',
      () async {
    // The lock file does not exist and never will: the directory is not
    // writable. `create(exclusive: true)` fails, the stat that follows fails
    // too because there is nothing to stat, and both of those used to
    // `continue` — skipping the deadline check AND the poll sleep. The result
    // was an unbounded 100%-CPU spin with the documented timeout never
    // applying and the real I/O error never surfaced.
    Process.runSync('chmod', ['500', dir.path]);
    addTearDown(() => Process.runSync('chmod', ['700', dir.path]));

    final lock = AtKeysFileLock(protected,
        timeout: const Duration(milliseconds: 300),
        pollInterval: const Duration(milliseconds: 20));

    final started = DateTime.now();
    await expectLater(
        lock.synchronized(() async => 1).timeout(const Duration(seconds: 4)),
        throwsA(isA<FileSystemException>().having((e) => e.message, 'message',
            contains('The last failure was'))),
        reason: 'the wait must be bounded even when the failure is not '
            'contention, and the timeout must name the real cause rather '
            'than blaming a process that holds nothing');
    expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 3)),
        reason: 'it must give up at its own deadline, not spin');
  });

  test('a restore never overwrites a lock taken while we were inspecting',
      () async {
    // Both `_breakStale` and `_release` rename lockPath aside before deciding
    // what to do with it, and that leaves the path vacant long enough for a
    // contender's exclusive create to succeed. Putting the claimed file back
    // over that new lock would evict a live holder and leave a stale
    // timestamp in its place, which the next contender breaks — two processes
    // in the critical section.
    final lock = AtKeysFileLock(protected);
    final claimed = File('${lock.lockPath}.claimed');

    // CONTROL — with lockPath vacant, the restore must still put it back.
    // Without this the test would pass on a restore that never restores.
    claimed.writeAsStringSync('an-earlier-holder\n');
    lock.restoreClaimed(claimed);
    expect(File(lock.lockPath).readAsStringSync(), 'an-earlier-holder\n',
        reason: 'a claimed lock must go back when nothing has taken the path');
    File(lock.lockPath).deleteSync();

    // THE CASE — a contender acquired during the window.
    claimed.writeAsStringSync('an-earlier-holder\n');
    File(lock.lockPath).writeAsStringSync('the-new-holder\n');
    lock.restoreClaimed(claimed);

    expect(File(lock.lockPath).readAsStringSync(), 'the-new-holder\n',
        reason: "the live holder's lock must survive; overwriting it puts a "
            'stale timestamp at lockPath, which the next contender breaks');
    expect(claimed.existsSync(), isFalse,
        reason: 'the spent claim must not be left beside the keyfile');
  });
}
