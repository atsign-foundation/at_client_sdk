import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/src/passkey/passkey_custody.dart';
import 'package:test/test.dart';

import '../support/bytes_passkey_sealer.dart';
import '../support/custody_fakes.dart';

const _atSign = '@alice';

bool _zeroed(Uint8List bytes) => bytes.every((b) => b == 0);

class _PrfPort implements PasskeyPort {
  _PrfPort(this.prf);

  final Uint8List prf;

  @override
  Future<PasskeyCreation> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) async =>
      (credentialId: Uint8List(1), prfEnabled: true);

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      (credentialId: Uint8List(1), prfFirst: prf);
}

/// Derives with [BytesPasskeyKeyDeriver] and keeps each derivation, to check
/// afterwards that the flow wiped it.
class _CapturingDeriver implements PasskeyKeyDeriver {
  _CapturingDeriver(this.derived);

  final List<PasskeyDerivation> derived;

  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async {
    final derivation = await const BytesPasskeyKeyDeriver().derive(prf, atSign);
    derived.add(derivation);
    return derivation;
  }
}

bool _sealerClosed(PasskeyDerivation d) =>
    (d.sealer as BytesRecordSealer).closed;

/// Derives as [BytesPasskeyKeyDeriver] does, from a copy of the PRF output, so
/// the output it is handed stays as it was.
class _CopyingDeriver implements PasskeyKeyDeriver {
  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) =>
      const BytesPasskeyKeyDeriver()
          .derive(PrfSecret(Uint8List.fromList(prf.output)), atSign);
}

/// Fails every derivation, leaving the PRF output as it was.
class _FailingDeriver implements PasskeyKeyDeriver {
  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async =>
      throw StateError('derivation failed');
}

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late List<PasskeyDerivation> derived;

  PasskeyCustody custody({FakeHints? withHints, PasskeyKeyDeriver? deriver}) =>
      PasskeyCustody(
          prf: PasskeyPrf(authenticator),
          pointerReader: server,
          gateway: gateway,
          credentials: withHints ?? hints,
          enrollmentIds: withHints ?? hints,
          persistence: FakePersistence(),
          retryDelay: Duration.zero,
          setupLock: FakeSetupLock(),
          setupLockPrefix: 'test:setup',
          deriver: deriver ?? _CapturingDeriver(derived));

  void forgetCaptured() {
    derived.clear();
    authenticator.issuedPrf.clear();
  }

  /// Every PRF output, kek and auth seed the flow touched is all zeroes.
  void expectWiped() {
    expect(authenticator.issuedPrf, isNotEmpty);
    expect(derived, isNotEmpty);
    for (final prf in authenticator.issuedPrf) {
      expect(_zeroed(prf), isTrue, reason: 'PRF output');
    }
    for (final keys in derived) {
      expect(_sealerClosed(keys), isTrue, reason: 'kek');
      expect(_zeroed(keys.authSeed), isTrue, reason: 'auth seed');
    }
  }

  /// The PRF outputs are all zeroes while a session holds the vault: its
  /// auth seed is zeroed and its sealer open until the session stops.
  void expectHeldBySession() {
    expect(authenticator.issuedPrf, isNotEmpty);
    for (final prf in authenticator.issuedPrf) {
      expect(_zeroed(prf), isTrue, reason: 'PRF output');
    }
    expect(derived, hasLength(1));
    expect(_sealerClosed(derived.single), isFalse, reason: 'kek');
    expect(_zeroed(derived.single.authSeed), isTrue, reason: 'auth seed');
  }

  setUp(() {
    server = FakeServer();
    gateway = FakeGateway(server);
    authenticator = FakeAuthenticator();
    hints = FakeHints();
    derived = [];
  });

  group('PrfSecret.wipe', () {
    test('overwrites the output with zeroes', () {
      final output = Uint8List.fromList(List.generate(32, (i) => i + 1));
      PrfSecret(output).wipe();
      expect(_zeroed(output), isTrue);
    });
  });

  group('PasskeyPrf', () {
    test('wipes a PRF output of the wrong length it refuses', () async {
      final prf = Uint8List.fromList(List.generate(31, (i) => i + 1));
      final port = _PrfPort(prf);
      await expectLater(
          PasskeyPrf(port).unlock(), throwsA(isA<PrfUnavailableException>()));
      expect(_zeroed(prf), isTrue);
    });
  });

  group('open', () {
    setUp(() async {
      await (await custody().onboard(atSign: _atSign, cram: 'cram')).stop();
      forgetCaptured();
    });

    test(
        'wipes the PRF at handover, and the kek and seed when the session '
        'stops', () async {
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expectHeldBySession();
      await session.stop();
      expectWiped();
    });

    test('wipes everything when the record is tampered with', () async {
      for (final id in server.documents.keys.toList()) {
        final record = server.documents[id]!;
        server.documents[id] = record.replaceFirst('"ct":"', '"ct":"AAAA');
      }
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyRecordAuthenticationException>()));
      expectWiped();
    });

    test('wipes everything when the public keys do not match', () async {
      server.publishedTag = 'v2';
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PublicKeyMismatchException>()));
      expectWiped();
    });

    test('wipes everything when the passkey is refused', () async {
      server.revoked.add('eid1');
      await expectLater(custody(withHints: FakeHints()).open(atSign: _atSign),
          throwsA(isA<PasskeyLostException>()));
      expectWiped();
    });

    test('wipes everything when remembering the device fails with an Error',
        () async {
      final broken = StateError('the hint store is broken');
      final fresh = FakeHints()
        ..failWrites = true
        ..writeFailure = broken;
      await expectLater(custody(withHints: fresh).open(atSign: _atSign),
          throwsA(same(broken)));
      expectWiped();
    });

    test(
        'a session opened when remembering the device fails with an Exception '
        'holds the vault until it stops', () async {
      final fresh = FakeHints()..failWrites = true;
      final session = await custody(withHints: fresh).open(atSign: _atSign);
      expectHeldBySession();
      await session.stop();
      expectWiped();
    });

    test('wipes the auth seed before it authenticates', () async {
      bool? seedZeroed;
      gateway.onAuthenticate =
          (_) => seedZeroed = _zeroed(derived.single.authSeed);
      await (await custody(withHints: FakeHints()).open(atSign: _atSign))
          .stop();
      expect(seedZeroed, isTrue);
    });
  });

  group('a deriver that leaves the PRF output as it was', () {
    void expectPrfWiped() {
      expect(authenticator.issuedPrf, isNotEmpty);
      for (final prf in authenticator.issuedPrf) {
        expect(_zeroed(prf), isTrue, reason: 'PRF output');
      }
    }

    test('onboarding and open wipe the PRF output once it is derived',
        () async {
      final onboarded = await custody(deriver: _CopyingDeriver())
          .onboard(atSign: _atSign, cram: 'cram');
      expectPrfWiped();
      await onboarded.stop();
      forgetCaptured();

      final opened =
          await custody(withHints: FakeHints(), deriver: _CopyingDeriver())
              .open(atSign: _atSign);
      expectPrfWiped();
      await opened.stop();
    });

    test('a derivation that fails still wipes the PRF output', () async {
      await expectLater(
          custody(deriver: _FailingDeriver())
              .onboard(atSign: _atSign, cram: 'cram'),
          throwsStateError);
      expectPrfWiped();
    });
  });

  group('onboard', () {
    test(
        'wipes the PRF at handover, and the kek and seed when the session '
        'stops', () async {
      final session = await custody().onboard(atSign: _atSign, cram: 'cram');
      expectHeldBySession();
      await session.stop();
      expectWiped();
    });

    test('wipes everything when the activation fails outright', () async {
      gateway.onActivate = () => throw StateError('cram refused');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expectWiped();
    });

    test('wipes the auth seed before it activates', () async {
      bool? seedZeroed;
      gateway.onActivate = () => seedZeroed = _zeroed(derived.single.authSeed);
      await (await custody().onboard(atSign: _atSign, cram: 'cram')).stop();
      expect(seedZeroed, isTrue);
    });

    test('wipes everything when the @keys document cannot be written',
        () async {
      server.documentPutFailures = 99;
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expectWiped();
    });

    test('wipes everything when completing the activation fails', () async {
      gateway.onAuthenticate =
          (session) => session.completeError = StateError('interrupted');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expectWiped();
    });
  });
}
