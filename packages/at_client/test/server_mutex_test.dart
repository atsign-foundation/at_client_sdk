/// The server mutex extension: what it sends, and what it refuses to send.
///
/// The scenario tests share their titles with
/// `features/at_client/server_mutex.feature`. What the atServer does with the
/// command is proven live, in the functional pack's
/// `server_mutex_live_test.dart`; every assertion here is over the command the
/// builder produced, as a raw literal.
library;

import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/client/server_mutex.dart' show ServerMutexHolder;
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey, pqSigningRootMintLockKey;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  AtSignLogger.root_level = 'shout';

  setUpAll(() => registerFallbackValue(FakeUpdateVerbBuilder()));

  /// A client of @alice under enrollment [enrollmentId] whose atServer answers
  /// an update with [onUpdate] and a local lookup with [onLookup], recording
  /// every command it is sent, and refusing any other verb by name.
  AtClient clientOf(List<String> sent,
      {String? enrollmentId = 'e-1',
      Future<String> Function()? onUpdate,
      Future<String> Function()? onLookup}) {
    final atClient = MockAtClient();
    final remote = MockRemoteSecondary();
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
    when(() => atClient.enrollmentId).thenReturn(enrollmentId);
    when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as VerbBuilder;
      sent.add(builder.buildCommand());
      if (builder is UpdateVerbBuilder) {
        return (onUpdate ?? () async => 'data:-1')();
      }
      if (builder is LLookupVerbBuilder && onLookup != null) {
        return onLookup();
      }
      throw StateError('unexpected verb: ${builder.runtimeType}');
    });
    return atClient;
  }

  final lockKey = AtKey.fromString('s1.session_mutexes.sshnp@alice');
  const ttl = Duration(seconds: 30);

  /// What the atServer throws on a second create of an immutable record, as
  /// the remote secondary hands it on: the shape the functional pack's
  /// `nskey_mint_lock_live_test.dart` observes against a live atServer.
  IllegalStateException heldElsewhere() =>
      IllegalStateException('Immutable records may not be updated');

  Matcher refusedNaming(String name) =>
      isA<ArgumentError>().having((e) => e.name, 'name', name);

  group('the create', () {
    test(
        'is one update carrying :nc, the ttl and immutable, valued with the '
        'enrollment id', () async {
      final sent = <String>[];
      await clientOf(sent).tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(sent, [
        'update:nc:ttl:30000:isEncrypted:false:immutable:true:'
            's1.session_mutexes.sshnp@alice e-1\n'
      ]);
    });

    test('names a client with no enrollment by the primary sentinel', () async {
      final sent = <String>[];
      await clientOf(sent, enrollmentId: null)
          .tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(sent.single, endsWith(' primary\n'));
    });

    test('writes the record every existing lock is held on, unchanged',
        () async {
      // NOTE: frozen. A client on an older release writes these names, and
      // one using the extension excludes it only while both name one record.
      final keys = {
        AtKey.fromString('42.session_mutexes.domain.rpcs.base@alice'):
            '42.session_mutexes.domain.rpcs.base@alice',
        AtKey.fromString('s1.session_mutexes.sshrvd@alice'):
            's1.session_mutexes.sshrvd@alice',
        nskeyMintLockKey('@alice', 'testing'): '_nskeylock.testing@alice',
        pqSigningRootMintLockKey('@alice'): '_rootlock@alice',
      };
      for (final entry in keys.entries) {
        final sent = <String>[];
        await clientOf(sent).tryAcquireServerMutex(entry.key, ttl: ttl);
        expect(sent.single, endsWith(':${entry.value} e-1\n'),
            reason: 'the record ${entry.value} must be written as named');
      }
    });

    test('fills in this atSign for a key that names no owner', () async {
      final sent = <String>[];
      await clientOf(sent).tryAcquireServerMutex(
          AtKey()
            ..key = 's1'
            ..namespace = 'session_mutexes.sshnp',
          ttl: ttl);
      expect(sent.single, endsWith(':s1.session_mutexes.sshnp@alice e-1\n'));
    });

    test(
        'gives a lease ending no later than the ttl after the create was '
        'sent', () async {
      final began = DateTime.now();
      late DateTime sentAt;
      final lease = await clientOf([], onUpdate: () async {
        sentAt = DateTime.now();
        return 'data:-1';
      }).tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(lease, isNotNull);
      expect(lease!.expiresAt.isAfter(sentAt.add(ttl)), isFalse,
          reason: 'the atServer starts the ttl once it has the command, so a '
              'lease stamped any later would outlive the lock');
      expect(lease.expiresAt.isBefore(began.add(ttl)), isFalse);
      expect(lease.isSpent, isFalse);
    });
  });

  group('the answer', () {
    test('is no lease when the atServer refuses a second create', () async {
      final lease =
          await clientOf([], onUpdate: () async => throw heldElsewhere())
              .tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(lease, isNull);
    });

    test('Any other failure is thrown to the caller', () async {
      final failure = AtTimeoutException('no answer');
      await expectLater(
          clientOf([], onUpdate: () async => throw failure)
              .tryAcquireServerMutex(lockKey, ttl: ttl),
          throwsA(same(failure)));
      final refused = IllegalStateException('some other illegal state');
      await expectLater(
          clientOf([], onUpdate: () async => throw refused)
              .tryAcquireServerMutex(lockKey, ttl: ttl),
          throwsA(same(refused)),
          reason: 'only the refusal of a second create means "held"; the '
              'same exception type saying anything else is a failure');
    });
  });

  group('the ttl', () {
    test('A ttl over 15 minutes is refused', () async {
      final sent = <String>[];
      await expectLater(
          clientOf(sent).tryAcquireServerMutex(lockKey,
              ttl: const Duration(minutes: 15, milliseconds: 1)),
          throwsA(refusedNaming('ttl')));
      expect(sent, isEmpty, reason: 'nothing is sent to the atServer');
    });

    test('A ttl of exactly 15 minutes is accepted', () async {
      final sent = <String>[];
      await clientOf(sent)
          .tryAcquireServerMutex(lockKey, ttl: const Duration(minutes: 15));
      expect(sent.single, startsWith('update:nc:ttl:900000:'));
    });

    test('A ttl of zero or less is refused', () async {
      for (final ttl in [
        Duration.zero,
        const Duration(milliseconds: -1),
        // NOTE: the ttl travels in whole milliseconds, where this is 0.
        const Duration(microseconds: 999),
      ]) {
        final sent = <String>[];
        await expectLater(
            clientOf(sent).tryAcquireServerMutex(lockKey, ttl: ttl),
            throwsA(refusedNaming('ttl')),
            reason: 'a ttl of $ttl');
        expect(sent, isEmpty, reason: 'nothing is sent for a ttl of $ttl');
      }
    });
  });

  group('the key', () {
    Future<void> expectRefused(String key) async {
      final sent = <String>[];
      await expectLater(
          clientOf(sent).tryAcquireServerMutex(AtKey.fromString(key), ttl: ttl),
          throwsA(refusedNaming('key')));
      expect(sent, isEmpty, reason: 'nothing is sent to the atServer');
      final looked = <String>[];
      await expectLater(
          clientOf(looked).holdsServerMutex(AtKey.fromString(key)),
          throwsA(refusedNaming('key')));
      expect(looked, isEmpty, reason: 'nor is it read');
    }

    test('A key owned by another atSign is refused', () async {
      await expectRefused('s1.session_mutexes.sshnp@bob');
    });

    test('A key shared with another atSign is refused', () async {
      await expectRefused('@bob:s1.session_mutexes.sshnp@alice');
    });

    test('A public key is refused', () async {
      await expectRefused('public:s1.session_mutexes.sshnp@alice');
    });

    test('and a cached or local key is refused too', () async {
      await expectRefused('cached:@alice:s1.session_mutexes.sshnp@bob');
      await expectRefused('local:s1.session_mutexes.sshnp@alice');
    });

    test('A key whose name carries another atSign is refused', () async {
      // NOTE: no flag on this key says shared; only its name as built does.
      final key = AtKey()
        ..key = '@bob:s1'
        ..namespace = 'session_mutexes.sshnp';
      final sent = <String>[];
      await expectLater(clientOf(sent).tryAcquireServerMutex(key, ttl: ttl),
          throwsA(refusedNaming('key')));
      expect(sent, isEmpty, reason: 'nothing is sent to the atServer');
    });

    test('a refusal names a key that names no owner with this atSign',
        () async {
      await expectLater(
          clientOf([]).tryAcquireServerMutex(
              AtKey()
                ..key = 's1'
                ..namespace = 'session_mutexes.sshnp'
                ..metadata = (Metadata()..isPublic = true),
              ttl: ttl),
          throwsA(isA<ArgumentError>().having((e) => e.invalidValue,
              'invalidValue', 'public:s1.session_mutexes.sshnp@alice')));
    });
  });

  group('reading a lock back, for at_client\'s own use', () {
    final expiry = DateTime.utc(2026, 10, 13, 12, 30);

    /// A lock record as llookup:all serves it, held by [holder].
    String record(String holder, {DateTime? expiresAt}) => 'data:${jsonEncode({
              'key': 's1.session_mutexes.sshnp@alice',
              'data': holder,
              'metaData': {'expiresAt': expiresAt?.toIso8601String()},
            })}';

    test('reads the record with llookup:all and compares its enrollment',
        () async {
      final sent = <String>[];
      expect(
          await clientOf(sent, onLookup: () async => record('e-1'))
              .holdsServerMutex(lockKey),
          isTrue);
      expect(sent, ['llookup:all:s1.session_mutexes.sshnp@alice\n']);
      expect(
          await clientOf([], onLookup: () async => record('e-2'))
              .holdsServerMutex(lockKey),
          isFalse);
    });

    test('is no when the record does not exist', () async {
      expect(
          await clientOf([],
                  onLookup: () async =>
                      throw KeyNotFoundException('no such key'))
              .holdsServerMutex(lockKey),
          isFalse);
    });

    test('throws any other failure to read it', () async {
      final failure = AtTimeoutException('no answer');
      await expectLater(
          clientOf([], onLookup: () async => throw failure)
              .holdsServerMutex(lockKey),
          throwsA(same(failure)));
    });

    test(
        'gives a lease on this enrollment\'s own lock ending at the '
        'record\'s own expiry', () async {
      final soon = DateTime.now().toUtc().add(const Duration(seconds: 10));
      final lease = await clientOf([],
              onLookup: () async => record('e-1', expiresAt: soon))
          .ownServerMutexLease(lockKey, ttl: ttl);
      expect(lease, isNotNull);
      expect(lease!.expiresAt, soon);
    });

    test(
        'caps a lease on a record expiring later than a fresh lease would, '
        'at the ttl from the read', () async {
      final began = DateTime.now();
      final lease = await clientOf([],
              onLookup: () async => record('e-1',
                  expiresAt:
                      DateTime.now().toUtc().add(const Duration(days: 1))))
          .ownServerMutexLease(lockKey, ttl: ttl);
      final ended = DateTime.now();
      expect(lease!.expiresAt.isAfter(ended.add(ttl)), isFalse,
          reason: 'never longer than a fresh lease taken at the read');
      expect(lease.expiresAt.isBefore(began.add(ttl)), isFalse);
    });

    test('refuses a ttl a fresh lease would refuse, before reading', () async {
      final looked = <String>[];
      await expectLater(
          clientOf(looked, onLookup: () async => record('e-1'))
              .ownServerMutexLease(lockKey,
                  ttl: const Duration(minutes: 15, milliseconds: 1)),
          throwsA(refusedNaming('ttl')));
      expect(looked, isEmpty);
    });

    test(
        'gives no lease on another enrollment\'s lock, or on one with no '
        'expiry', () async {
      expect(
          await clientOf([],
                  onLookup: () async => record('e-2', expiresAt: expiry))
              .ownServerMutexLease(lockKey, ttl: ttl),
          isNull);
      expect(
          await clientOf([], onLookup: () async => record('e-1'))
              .ownServerMutexLease(lockKey, ttl: ttl),
          isNull,
          reason: 'a lease must end no later than its lock');
    });

    test('throws a FormatException for a reply that is not a record', () async {
      await expectLater(
          clientOf([], onLookup: () async => 'data:1')
              .holdsServerMutex(lockKey),
          throwsA(isA<FormatException>()));
    });
  });

  group('the local store', () {
    test('Taking a lock writes nothing to the local store', () async {
      const atSign = '@servermutexlocal';
      final remote = MockRemoteSecondary();
      when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
          .thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as VerbBuilder;
        if (builder is UpdateVerbBuilder) return 'data:-1';
        throw StateError('unexpected verb: ${builder.runtimeType}');
      });
      final atClient = await AtClientImpl.create(
          atSign, 'sshnp', AtClientPreference(),
          remoteSecondary: remote,
          storage:
              InMemoryAtClientStorage(atSign: atSign, closedByClient: true));
      addTearDown(atClient.stop);

      final key = AtKey.fromString('s1.session_mutexes.sshnp$atSign');
      expect(await atClient.tryAcquireServerMutex(key, ttl: ttl), isNotNull);
      await expectLater(
          atClient.get(AtKey.fromString('s1.session_mutexes.sshnp$atSign')),
          throwsA(isA<AtKeyNotFoundException>()));

      // NOTE: the control. A local write of the same shape is found by the
      // same read, so the absence above is not a read that cannot see it.
      final control = AtKey.fromString('control.session_mutexes.sshnp$atSign');
      await atClient.put(control, 'a value',
          putRequestOptions: PutRequestOptions()..shouldEncrypt = false);
      expect((await atClient.get(control)).value, 'a value');
    });
  });
}
