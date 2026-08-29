import 'dart:async';

import 'package:at_client/at_client.dart';
import 'package:at_client/src/signing/signing_key_mint_barrier.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

/// The barrier is what every signer waits on before reading which keys may
/// sign. Its contract is that it completes on every path — and the case these
/// tests pin is the one that contract cannot cover: a startup that never
/// returns at all, because a step BEFORE the mint blocked.
///
/// Measured 2026-08-29: `collectConveyedKeys` is step 2 of 12 and
/// `mintInUseSigningKeys` is step 4, so a step-2 stall leaves the barrier
/// unsettled for the life of the process. Unbounded, that deadlocked every
/// signer in the client — an `at_activate approve` waiting to sign the envelope
/// it had just sealed did not terminate through a six-minute test timeout or a
/// seven-minute manual bound.
void main() {
  late Duration originalWait;

  setUp(() => originalWait = signingKeyMintWait);
  tearDown(() => signingKeyMintWait = originalWait);

  group('awaitSigningKeyMint', () {
    test('returns the elapsed bound when the mint never settles', () async {
      // The defect's shape: a barrier registered by the bootstrap constructor
      // whose startup is stuck before the mint step, so nothing ever completes
      // it.
      signingKeyMintWait = const Duration(milliseconds: 50);
      final client = MockAtClient();
      registerSigningKeyMintBarrier(client, Completer<void>().future);

      expect(await awaitSigningKeyMint(client), signingKeyMintWait,
          reason: 'a signer must be told the wait elapsed so it can sign with '
              'what the keyfile holds. Returning null here would be '
              'indistinguishable from a settled mint, and awaiting forever is '
              'the deadlock this exists to prevent');
    });

    test('returns null once the mint settles', () async {
      // Control 1: the ordinary path. It must NOT report a timeout, or every
      // signer would log a warning and the assertion above would pass just as
      // well for a bound that never waits at all.
      signingKeyMintWait = const Duration(seconds: 30);
      final client = MockAtClient();
      final settled = Completer<void>();
      registerSigningKeyMintBarrier(client, settled.future);
      unawaited(Future<void>.delayed(
          const Duration(milliseconds: 10), settled.complete));

      expect(await awaitSigningKeyMint(client), isNull,
          reason: 'a mint that settles inside the bound is the normal case and '
              'must be silent');
    });

    test('returns null when no barrier was ever registered', () async {
      // Control 2: a client built without the PQ startup has no mint in flight.
      // It must not wait at all — this is the fast path, and treating an absent
      // barrier as a timeout would make every such client warn.
      signingKeyMintWait = const Duration(seconds: 30);

      expect(await awaitSigningKeyMint(MockAtClient()), isNull,
          reason: 'nothing registered a mint, so there is nothing to wait for');
    });

    test('waits at least the bound before giving up', () async {
      // Pins the bound as a bound rather than as an immediate return: without
      // this, a signingKeyMintWait of zero would satisfy the first test and
      // reintroduce the window the barrier exists to close — signing before
      // the mint publishes produces an envelope nothing can verify.
      signingKeyMintWait = const Duration(milliseconds: 200);
      final client = MockAtClient();
      registerSigningKeyMintBarrier(client, Completer<void>().future);

      final started = DateTime.now();
      await awaitSigningKeyMint(client);
      final waited = DateTime.now().difference(started);

      expect(waited, greaterThanOrEqualTo(const Duration(milliseconds: 150)),
          reason: 'the bound must actually elapse; a signer that gives up '
              'immediately signs in exactly the window the barrier closes');
    });
  });
}
