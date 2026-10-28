/// What the mint lock does when the lock it meets is **its own**.
///
/// The winner never releases — the ttl does — so for the whole cooldown a
/// client that took the lock and then re-entered loses the election to
/// itself. `ownLockIsNotContention` is what lets an idempotent critical
/// section proceed anyway, and it is off by default.
library;

import 'dart:convert';

import 'package:at_client/at_client.dart'
    show PqSigningRoot, PublishedNskeyKeyRing, ServerMutexLease;
import 'package:at_client/src/crypto/nskey/mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart'
    show IllegalStateException, KeyNotFoundException;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  const atSign = '@alice';
  const ours = 'enroll-a';

  setUpAll(() => registerFallbackValue(FakeUpdateVerbBuilder()));

  final lockKey =
      nskeyMintLockKey(atSign, 'testing', ttl: const Duration(minutes: 2));

  /// An atServer holding [heldBy]'s lock on the one record these tests turn
  /// on, refusing every take the way it refuses a second immutable create,
  /// and answering a read of the lock as llookup:all does, with its holder
  /// and [expiresAt]. A null [heldBy] is a lock that expired before it could
  /// be read.
  ///
  /// A fresh `MintLock` per call on purpose: a restart is a new instance, and
  /// reusing one would let its in-process guard answer instead of the wire.
  MintLock lockedBy(String? heldBy,
      {required List<String> lookups, DateTime? expiresAt}) {
    expiresAt ??= DateTime.now().toUtc().add(const Duration(minutes: 1));
    final atClient = MockAtClient();
    final remote = MockRemoteSecondary();
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(ours);
    when(() => remote.executeVerb(any())).thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as VerbBuilder;
      if (builder is UpdateVerbBuilder) {
        throw IllegalStateException('Immutable records may not be updated');
      }
      if (builder is LLookupVerbBuilder) {
        lookups.add(builder.buildCommand());
        if (heldBy == null) throw KeyNotFoundException('$lockKey not found');
        return 'data:${jsonEncode({
              'key': '$lockKey',
              'data': heldBy,
              'metaData': {'expiresAt': expiresAt!.toIso8601String()},
            })}';
      }
      throw StateError('unexpected verb: ${builder.runtimeType}');
    });
    return MintLock(atClient);
  }

  group('a client that re-enters inside its own cooldown', () {
    test('is refused by default, and never asks whose lock it is', () async {
      final lookups = <String>[];
      var ran = false;

      final outcome = await lockedBy(ours, lookups: lookups)
          .withLock<String>(lockKey, (lease) async {
        ran = true;
        return 'minted';
      });

      expect(outcome, isNull,
          reason: 'the default treats any refusal as contention, so a client '
              'whose previous instance died before publishing gets nothing '
              'done for the rest of the ttl');
      expect(ran, isFalse, reason: 'the critical section never ran');
      expect(lookups, isEmpty,
          reason: 'and it does not even look: ownership is only read when a '
              'caller opts in, so the lock being OURS is invisible here');
    });

    test('proceeds when the caller opts in, on the same refusal', () async {
      final lookups = <String>[];
      var ran = false;

      final outcome = await lockedBy(ours, lookups: lookups)
          .withLock<String>(lockKey, (lease) async {
        ran = true;
        return 'minted';
      }, ownLockIsNotContention: true);

      expect(outcome, 'minted');
      expect(ran, isTrue,
          reason: 'the only difference from the arm above is the flag');
      expect(lookups.single, 'llookup:all:${lockKey.toString()}\n',
          reason: 'it reads the lock to find out whose it is, and the wire '
              'token is the enrollment id, which survives a restart');
    });

    test('and opting in still loses to a DIFFERENT enrollment', () async {
      final lookups = <String>[];
      var ran = false;

      final outcome = await lockedBy('enroll-b', lookups: lookups)
          .withLock<String>(lockKey, (lease) async {
        ran = true;
        return 'minted';
      }, ownLockIsNotContention: true);

      expect(outcome, isNull);
      expect(ran, isFalse,
          reason: 'what the cooldown protects against is a SECOND enrollment '
              'minting, and opting in must leave that untouched');
      expect(lookups, hasLength(1),
          reason: 'it asked, and the answer was somebody else');
    });
  });

  group('Given this enrollment\'s own mint lock from earlier in its cooldown',
      () {
    test(
        'when it adopts that lock, then its lease ends at the lock record\'s '
        'own expiry', () async {
      final expiresAt = DateTime.now().toUtc().add(const Duration(seconds: 37));
      ServerMutexLease? held;

      final outcome = await lockedBy(ours, lookups: [], expiresAt: expiresAt)
          .withLock<String>(lockKey, (lease) async {
        held = lease;
        return 'minted';
      }, ownLockIsNotContention: true);

      expect(outcome, 'minted');
      expect(held!.expiresAt, expiresAt,
          reason: 'the lock was taken earlier, so a full ttl from now would '
              'outlive it');
    });

    test(
        'when the lock record expires later than a fresh lease would, then '
        'the adopted lease ends a lock ttl after the read', () async {
      const lockTtl = Duration(minutes: 2);
      final began = DateTime.now();
      ServerMutexLease? held;

      await lockedBy(ours,
              lookups: [],
              expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)))
          .withLock<String>(lockKey, (lease) async {
        held = lease;
        return 'minted';
      }, ownLockIsNotContention: true);
      final ended = DateTime.now();

      expect(held!.expiresAt.isAfter(ended.add(lockTtl)), isFalse,
          reason: 'never longer than a fresh lease on this lock');
      expect(held!.expiresAt.isBefore(began.add(lockTtl)), isFalse);
    });
  });

  group('Given a lock that expired before it could be read', () {
    test('when the caller opts in, then it is not adopted', () async {
      var ran = false;

      final outcome = await lockedBy(null, lookups: [])
          .withLock<String>(lockKey, (lease) async {
        ran = true;
        return 'minted';
      }, ownLockIsNotContention: true);

      expect(outcome, isNull);
      expect(ran, isFalse);
    });
  });

  group('Given a lock key whose ttl is over 15 minutes', () {
    test('when withLock runs, then it throws rather than declining', () async {
      var ran = false;
      final longKey = nskeyMintLockKey(atSign, 'testing',
          ttl: const Duration(minutes: 15, milliseconds: 1));

      await expectLater(
          lockedBy(ours, lookups: []).withLock<String>(longKey, (lease) async {
            ran = true;
            return 'minted';
          }),
          throwsA(isA<ArgumentError>()),
          reason: 'a ttl over the cap is a mistake in the call, not a lock '
              'someone else holds, so it is not swallowed as one');
      expect(ran, isFalse);
    });
  });

  group('Given a ring or signing root built with a lockTtl over 15 minutes',
      () {
    const tooLong = Duration(minutes: 15, milliseconds: 1);
    final namesLockTtl =
        isA<ArgumentError>().having((e) => e.name, 'name', 'lockTtl');

    test(
        'when it is constructed, then it throws an ArgumentError naming '
        'lockTtl', () {
      expect(() => PublishedNskeyKeyRing(MockAtClient(), lockTtl: tooLong),
          throwsA(namesLockTtl));
      expect(() => PqSigningRoot(MockAtClient(), lockTtl: tooLong),
          throwsA(namesLockTtl));
    });

    test('and one of exactly 15 minutes is accepted', () {
      const longest = Duration(minutes: 15);
      expect(PublishedNskeyKeyRing(MockAtClient(), lockTtl: longest).lockTtl,
          longest);
      expect(PqSigningRoot(MockAtClient(), lockTtl: longest).lockTtl, longest);
    });
  });
}
