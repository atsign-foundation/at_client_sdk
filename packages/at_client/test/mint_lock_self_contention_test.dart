/// What the mint lock does when the lock it meets is **its own**.
///
/// The winner never releases — the ttl does — so for the whole cooldown a
/// client that took the lock and then re-entered is refused, as it would be by
/// any other client's lock.
library;

import 'dart:convert';

import 'package:at_client/at_client.dart'
    show PqSigningRoot, PublishedNskeyKeyRing;
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

  /// An atServer holding the one record these tests turn on: the first create
  /// takes it, every later one is refused as a second immutable create is,
  /// and a read answers as llookup:all does, with the value the winner wrote.
  ///
  /// Each call to the returned function is a fresh `MintLock` of this
  /// enrollment on that atServer: a restart is a new instance, and reusing one
  /// would let its in-process guard answer instead of the wire.
  ({MintLock Function() restart, List<String> lookups}) atServer() {
    final lookups = <String>[];
    String? held;
    MintLock restart() {
      final atClient = MockAtClient();
      final remote = MockRemoteSecondary();
      when(() => atClient.getRemoteSecondary()).thenReturn(remote);
      when(() => atClient.getCurrentAtSign()).thenReturn(atSign);
      when(() => atClient.enrollmentId).thenReturn(ours);
      when(() => remote.executeVerb(any())).thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as VerbBuilder;
        if (builder is UpdateVerbBuilder) {
          if (held != null) {
            throw IllegalStateException('Immutable records may not be updated');
          }
          held = builder.value as String;
          return 'data:-1';
        }
        if (builder is LLookupVerbBuilder) {
          lookups.add(builder.buildCommand());
          if (held == null) throw KeyNotFoundException('$lockKey not found');
          return 'data:${jsonEncode({
                'key': '$lockKey',
                'data': held,
                'metaData': {
                  'expiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(minutes: 1))
                      .toIso8601String()
                },
              })}';
        }
        throw StateError('unexpected verb: ${builder.runtimeType}');
      });
      return MintLock(atClient);
    }

    return (restart: restart, lookups: lookups);
  }

  group('Given this enrollment\'s own mint lock from earlier in its cooldown',
      () {
    test(
        'when a new instance of the same enrollment asks for it, then it is '
        'refused and never asks whose lock it is', () async {
      final server = atServer();
      expect(
          await server
              .restart()
              .withLock<String>(lockKey, (_) async => 'first'),
          'first',
          reason: 'the control: the lock is free until somebody takes it, and '
              'taking it runs the critical section');
      var ran = false;

      final outcome =
          await server.restart().withLock<String>(lockKey, (lease) async {
        ran = true;
        return 'minted';
      });

      expect(outcome, isNull,
          reason: 'every refusal is contention, whichever client took the '
              'lock, so a client whose earlier run stopped before publishing '
              'waits out the ttl');
      expect(ran, isFalse, reason: 'the critical section never ran');
      expect(server.lookups, isEmpty,
          reason: 'and it does not read the lock: whose it is decides '
              'nothing');
    });
  });

  group('Given a lock key whose ttl is over 15 minutes', () {
    test('when withLock runs, then it throws rather than declining', () async {
      var ran = false;
      final longKey = nskeyMintLockKey(atSign, 'testing',
          ttl: const Duration(minutes: 15, milliseconds: 1));

      await expectLater(
          atServer().restart().withLock<String>(longKey, (lease) async {
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
