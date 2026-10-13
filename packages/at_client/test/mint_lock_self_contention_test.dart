/// What the mint lock does when the lock it meets is **its own**.
///
/// The winner never releases — the ttl does — so for the whole cooldown a
/// client that took the lock and then re-entered loses the election to
/// itself. `ownLockIsNotContention` is what lets an idempotent critical
/// section proceed anyway, and it is off by default.
library;

import 'package:at_client/src/crypto/nskey/mint_lock.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show nskeyMintLockKey;
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart' show IllegalStateException;
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
  /// and answering a read of the lock with its holder.
  ///
  /// A fresh `MintLock` per call on purpose: a restart is a new instance, and
  /// reusing one would let its in-process guard answer instead of the wire.
  MintLock lockedBy(String heldBy, {required List<String> lookups}) {
    final atClient = MockAtClient();
    final remote = MockRemoteSecondary();
    when(() => atClient.getRemoteSecondary()).thenReturn(remote);
    when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
    when(() => atClient.enrollmentId).thenReturn(ours);
    when(() => remote.executeVerb(any(), sync: any(named: 'sync')))
        .thenAnswer((inv) async {
      final builder = inv.positionalArguments[0] as VerbBuilder;
      if (builder is UpdateVerbBuilder) {
        throw IllegalStateException('Immutable records may not be updated');
      }
      if (builder is LLookupVerbBuilder) {
        lookups.add(builder.buildCommand());
        return 'data:$heldBy';
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
      expect(lookups.single, 'llookup:${lockKey.toString()}\n',
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
}
