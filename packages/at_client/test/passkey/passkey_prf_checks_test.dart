import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';

const _atSign = '@alice🛠';

/// An authenticator whose assertions return [prfFirst] as their PRF output,
/// in place of the passkey's own, once [replacesPrf] is set.
class _Authenticator extends FakeAuthenticator {
  var replacesPrf = false;
  Uint8List? prfFirst;

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    final assertion =
        await super.get(evalInput: evalInput, allowCredential: allowCredential);
    if (!replacesPrf) return assertion;
    return (credentialId: assertion.credentialId, prfFirst: prfFirst);
  }
}

/// Derives like [BytesPasskeyKeyDeriver] and counts the derivations.
class _CountingDeriver implements PasskeyKeyDeriver {
  var derivations = 0;

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) {
    derivations++;
    return const BytesPasskeyKeyDeriver().derive(prf, atSign);
  }
}

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late _Authenticator authenticator;
  late _CountingDeriver deriver;

  PasskeyCustody custody() {
    final hints = FakeHints();
    return PasskeyCustody(
        prf: PasskeyPrf(authenticator),
        deriver: deriver,
        pointerReader: server,
        gateway: gateway,
        hints: hints,
        persistence: FakePersistence(),
        retryDelay: Duration.zero,
        setupLock: FakeSetupLock(),
        setupLockPrefix: 'test:setup');
  }

  setUp(() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = _Authenticator();
    deriver = _CountingDeriver();
  });

  test('a usable PRF output is derived once and activated once', () async {
    await custody().onboard(atSign: _atSign, cram: 'cram');
    expect(deriver.derivations, 1);
    expect(gateway.activated, hasLength(1));
    expect(authenticator.signalled, isEmpty);
  });

  test('A PRF output of all zeroes is refused before any key is derived',
      () async {
    authenticator
      ..replacesPrf = true
      ..prfFirst = Uint8List(32);
    await expectLater(custody().onboard(atSign: _atSign, cram: 'cram'),
        throwsA(isA<PrfUnavailableException>()));
    expect(deriver.derivations, 0);
    expect(gateway.activated, isEmpty);
  });

  for (final (outcome, assertionFails, failure) in [
    (
      'fails because the user cancels',
      (_Authenticator a) => a.yieldsNoCredential = true,
      isA<PasskeyCeremonyException>()
    ),
    (
      'returns no PRF output',
      (_Authenticator a) => a
        ..replacesPrf = true
        ..prfFirst = null,
      isA<PrfUnavailableException>()
    ),
    (
      'returns 32 zero bytes',
      (_Authenticator a) => a
        ..replacesPrf = true
        ..prfFirst = Uint8List(32),
      isA<PrfUnavailableException>()
    ),
  ]) {
    test(
        'A passkey created without a usable PRF output is reported as '
        'unknown: $outcome', () async {
      assertionFails(authenticator);
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsA(failure));
      expect(authenticator.creates, 1);
      expect(authenticator.signalled, [
        Uint8List.fromList([1])
      ]);
      expect(gateway.activated, isEmpty);
      expect(deriver.derivations, 0);
    });
  }
}
