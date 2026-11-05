/// The server mutex extension: what it sends, and what it refuses to send.
///
/// The scenario tests share their titles with
/// `features/at_client/server_mutex.feature`. What the atServer does with the
/// command is proven live, in the functional pack's
/// `server_mutex_live_test.dart`; every assertion here is over the command the
/// builder produced, as a raw literal.
library;

import 'dart:isolate';

import 'package:at_client/at_client_io.dart';
import 'package:at_client/memory.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey, pqSigningRootMintLockKey;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';
import 'test_utils/no_keys.dart';
import 'test_utils/transport.dart';

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
    when(() => remote.executeVerb(any())).thenAnswer((inv) async {
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
        'enrollment id and this isolate\'s nonce', () async {
      final sent = <String>[];
      await clientOf(sent).tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(sent, [
        matches(RegExp(r'^update:nc:ttl:30000:isEncrypted:false:immutable:true:'
            r's1\.session_mutexes\.sshnp@alice e-1:[0-9a-f]{32}\n$'))
      ]);
    });

    test('names a client with no enrollment by the primary sentinel', () async {
      final sent = <String>[];
      await clientOf(sent, enrollmentId: null)
          .tryAcquireServerMutex(lockKey, ttl: ttl);
      expect(sent.single, matches(RegExp(r' primary:[0-9a-f]{32}\n$')));
    });

    test('Two processes of one enrollment write different lock values',
        () async {
      final sent = <String>[];
      await clientOf(sent).tryAcquireServerMutex(lockKey, ttl: ttl);
      await clientOf(sent).tryAcquireServerMutex(lockKey, ttl: ttl);
      final elsewhere = await Isolate.run(_lockValueInThisIsolate);

      final here = sent.map(_valueOf).toList();
      expect(here[0], here[1],
          reason: 'the control: one isolate writes one value, so the '
              'difference below is the isolate and nothing else');
      expect(elsewhere.split(':').first, 'e-1',
          reason: 'the control: the other isolate wrote under the same '
              'enrollment');
      expect(elsewhere, isNot(here[0]));
      expect(here[0], isNot('e-1'),
          reason: 'a release candidate reads a lock holding exactly its own '
              'enrollment id as its own, and mints under it');
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
        expect(sent.single, contains(':${entry.value} e-1:'),
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
      expect(sent.single, contains(':s1.session_mutexes.sshnp@alice e-1:'));
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

    test('gives a lease already spent when the create outlives the ttl',
        () async {
      final lease = await clientOf([], onUpdate: () async {
        await Future.delayed(const Duration(milliseconds: 60));
        return 'data:-1';
      }).tryAcquireServerMutex(lockKey, ttl: const Duration(milliseconds: 20));
      expect(lease!.isSpent, isTrue,
          reason: 'the atServer starts the ttl once it has the command, so '
              'the lease counts from before the send');
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

  group('the local store', () {
    test('Taking a lock writes nothing to the local store', () async {
      const atSign = '@servermutexlocal';
      final remote = MockRemoteSecondary();
      when(() => remote.executeVerb(any())).thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as VerbBuilder;
        if (builder is UpdateVerbBuilder) return 'data:-1';
        throw StateError('unexpected verb: ${builder.runtimeType}');
      });
      final atClient = await AtClientImpl.create(
          atSign, 'sshnp', AtClientPreference(),
          lookUps: secureSocketLookUps(),
          secondaryAddressFinder: atDirectoryOf(AtClientPreference()),
          atKeysIo: noKeysFor(atSign),
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

  group('the lease', () {
    test('runs out on elapsed time, not on the wall clock', () {
      final behind = ServerMutexLease.timed(
          lockKey,
          DateTime.now().subtract(const Duration(hours: 1)),
          Stopwatch()..start(),
          const Duration(minutes: 1));
      expect(behind.isSpent, isFalse,
          reason: 'a wall clock moved past expiresAt does not end it');
      final ahead = ServerMutexLease.timed(
          lockKey,
          DateTime.now().add(const Duration(hours: 1)),
          Stopwatch()..start(),
          Duration.zero);
      expect(ahead.isSpent, isTrue,
          reason: 'a wall clock short of expiresAt does not extend it');
    });
  });
}

/// The value of the lock in the update [command] sends.
String _valueOf(String command) =>
    command.substring(command.lastIndexOf(' ') + 1).trim();

/// The value a client of enrollment `e-1` writes to a lock in the isolate this
/// runs in.
Future<String> _lockValueInThisIsolate() async {
  registerFallbackValue(FakeUpdateVerbBuilder());
  final atClient = MockAtClient();
  final remote = MockRemoteSecondary();
  String? value;
  when(() => atClient.getRemoteSecondary()).thenReturn(remote);
  when(() => atClient.getCurrentAtSign()).thenReturn('@alice');
  when(() => atClient.enrollmentId).thenReturn('e-1');
  when(() => remote.executeVerb(any())).thenAnswer((inv) async {
    value = (inv.positionalArguments[0] as UpdateVerbBuilder).value as String;
    return 'data:-1';
  });
  await atClient.tryAcquireServerMutex(
      AtKey.fromString('s1.session_mutexes.sshnp@alice'),
      ttl: const Duration(seconds: 30));
  return value!;
}
