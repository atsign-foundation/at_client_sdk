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

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late List<PasskeyDerivation> derived;

  PasskeyCustody custody({FakeHints? withHints}) => PasskeyCustody(
      prf: PasskeyPrf(authenticator),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      persistence: FakePersistence(),
      pendingStore: FakePendingStore(),
      retryDelay: Duration.zero,
      setupLock: FakeSetupLock(),
      setupLockPrefix: 'test:setup',
      deriver: _CapturingDeriver(derived));

  void forgetCaptured() {
    derived.clear();
    authenticator.issuedPrf.clear();
    gateway.seedBuffers.clear();
  }

  /// Every PRF output, kek and auth seed the flow touched is all zeroes
  /// except [alive], which the flow handed to a still-open session.
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
    for (final seed in gateway.seedBuffers) {
      {
        expect(_zeroed(seed), isTrue, reason: 'auth seed given to gateway');
      }
    }
  }

  /// The PRF outputs are all zeroes while the client holds the vault: its
  /// auth seed is zeroed and its sealer open until the client stops.
  void expectHeldByClient() {
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
        'wipes the PRF at handover, and the kek and seed when the client stops',
        () async {
      final client =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expectHeldByClient();
      await client.stop();
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

    test('wipes everything when remembering the device fails', () async {
      final fresh = FakeHints()..failWrites = true;
      await expectLater(
          custody(withHints: fresh).open(atSign: _atSign), throwsStateError);
      expectWiped();
    });
  });

  group('onboard', () {
    test(
        'wipes the PRF at handover, and the kek and seed when the client stops',
        () async {
      final client = await custody().onboard(atSign: _atSign, cram: 'cram');
      expectHeldByClient();
      await client.stop();
      expectWiped();
    });

    test('wipes everything when the activation fails outright', () async {
      gateway.onActivate = () => throw StateError('cram refused');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expectWiped();
    });

    test('a resumable handle keeps its keys until the resumed client stops',
        () async {
      server.documentPutFailures = 3;
      late OnboardingIncompleteException incomplete;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        incomplete = e;
      }
      expect(_sealerClosed(derived.single), isFalse);
      final client = await incomplete.pending.resume();
      expectHeldByClient();
      await client.stop();
      expectWiped();
    });

    test('abandoning a handle wipes its keys', () async {
      server.documentPutFailures = 3;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        await e.pending.abandon();
      }
      expectWiped();
    });

    test(
        'an unfinished activation keeps the seed until the resumed client stops',
        () async {
      gateway.activationUnfinished = true;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        expect(_zeroed(derived.single.authSeed), isFalse);
        expect(_sealerClosed(derived.single), isFalse);
        final client = await e.pending.resume();
        expectHeldByClient();
        await client.stop();
        expectWiped();
      }
    });

    test('an unfinished activation wipes the seed when abandoned', () async {
      gateway.activationUnfinished = true;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        expect(_zeroed(derived.single.authSeed), isFalse);
        await e.pending.abandon();
      }
      expectWiped();
    });
  });
}
