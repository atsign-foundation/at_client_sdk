import 'dart:typed_data';

import 'package:at_client_wasm/src/keys/passkey_port.dart';
import 'package:at_client_wasm/src/keys/passkey_record_keys.dart';
import 'package:at_client_wasm/src/keys/passkey_record.dart';
import 'package:at_client_wasm/src/keys/unlock_secret.dart';
import 'package:at_client_wasm/src/session/passkey_custody.dart';
import 'package:test/test.dart';

import 'custody_fakes.dart';

const _atSign = '@alice';
const _otp = 'ABC123';

bool _zeroed(Uint8List bytes) => bytes.every((b) => b == 0);

class _PrfPort implements PasskeyPort {
  _PrfPort(this.prf);

  final Uint8List prf;

  @override
  Future<Uint8List> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) async =>
      Uint8List(1);

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      (credentialId: Uint8List(1), prfFirst: prf);
}

void main() {
  late FakeServer server;
  late FakeGateway gateway;
  late FakeAuthenticator authenticator;
  late FakeHints hints;
  late List<RecordKeys> derived;

  PasskeyCustody custody({FakeHints? withHints}) => PasskeyCustody(
      kek: PasskeyKek(authenticator),
      pointerReader: server,
      gateway: gateway,
      credentials: withHints ?? hints,
      enrollmentIds: withHints ?? hints,
      persistence: FakePersistence(),
      retryDelay: Duration.zero,
      setupLock: FakeSetupLock(),
      deriveKeys: (prf, atSign) async {
        final keys = await RecordKeys.derive(prf, atSign);
        derived.add(keys);
        return keys;
      });

  void forgetCaptured() {
    derived.clear();
    authenticator.issuedPrf.clear();
    gateway.seedBuffers.clear();
  }

  /// Every PRF output, kek and auth seed the flow touched is all zeroes
  /// except [alive], which the flow handed to a still-open session.
  void expectWiped({Uint8List? alive}) {
    expect(authenticator.issuedPrf, isNotEmpty);
    expect(derived, isNotEmpty);
    for (final prf in authenticator.issuedPrf) {
      expect(_zeroed(prf), isTrue, reason: 'PRF output');
    }
    for (final keys in derived) {
      expect(_zeroed(keys.kek), isTrue, reason: 'kek');
      expect(_zeroed(keys.authSeed), isTrue, reason: 'auth seed');
    }
    for (final seed in gateway.seedBuffers) {
      if (!identical(seed, alive)) {
        expect(_zeroed(seed), isTrue, reason: 'auth seed given to gateway');
      }
    }
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

  group('RecordKeys.wipe', () {
    test('overwrites the kek and the auth seed', () async {
      final prf = Uint8List.fromList(List.generate(32, (i) => i));
      final keys = await RecordKeys.derive(PrfSecret(prf), _atSign);
      expect(_zeroed(keys.kek), isFalse);
      keys.wipe();
      expect(_zeroed(keys.kek), isTrue);
      expect(_zeroed(keys.authSeed), isTrue);
    });

    test('derive leaves the PRF output to its owner', () async {
      final prf = Uint8List.fromList(List.generate(32, (i) => i + 1));
      await RecordKeys.derive(PrfSecret(prf), _atSign);
      expect(_zeroed(prf), isFalse);
    });
  });

  group('PasskeyKek', () {
    test('wipes a PRF output of the wrong length it refuses', () async {
      final prf = Uint8List.fromList(List.generate(31, (i) => i + 1));
      final port = _PrfPort(prf);
      await expectLater(
          PasskeyKek(port).unlock(), throwsA(isA<PrfUnavailableException>()));
      expect(_zeroed(prf), isTrue);
    });
  });

  group('enroll', () {
    test('wipes the PRF, kek and seed, keeping the seed in the session',
        () async {
      final session = await custody().enroll(atSign: _atSign, otp: _otp);
      expect(_zeroed(session.authSeed), isFalse);
      expectWiped();
      await session.close();
      expect(_zeroed(session.authSeed), isTrue);
    });

    test('with an existing passkey wipes the asserted PRF', () async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      forgetCaptured();
      server.seedByEnrollment.clear();
      final session = await custody()
          .enroll(atSign: _atSign, otp: _otp, existingPasskey: true);
      expectWiped();
      await session.close();
    });

    test('wipes everything when the enrollment is refused', () async {
      await custody().enroll(atSign: _atSign, otp: _otp);
      forgetCaptured();
      authenticator.current = Uint8List.fromList([1]);
      await expectLater(
          custody().enroll(atSign: _atSign, otp: _otp, existingPasskey: true),
          throwsA(isA<KeyAlreadyEnrolledException>()));
      expectWiped();
    });
  });

  group('open', () {
    setUp(() async {
      await (await custody().enroll(atSign: _atSign, otp: _otp)).close();
      forgetCaptured();
    });

    test('wipes the PRF and kek, keeping the seed in the session', () async {
      final session =
          await custody(withHints: FakeHints()).open(atSign: _atSign);
      expect(_zeroed(session.authSeed), isFalse);
      expectWiped(alive: session.authSeed);
      await session.close();
      expect(_zeroed(session.authSeed), isTrue);
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

  group('close', () {
    test('wipes the seed, and twice is harmless', () async {
      final session = await custody().enroll(atSign: _atSign, otp: _otp);
      await session.close();
      await session.close();
      expect(_zeroed(session.authSeed), isTrue);
    });
  });

  group('onboard', () {
    test('wipes the PRF, kek and seed, keeping the seed in the session',
        () async {
      final session = await custody().onboard(atSign: _atSign, cram: 'cram');
      expect(_zeroed(session.authSeed), isFalse);
      expectWiped();
      await session.close();
      expect(_zeroed(session.authSeed), isTrue);
    });

    test('wipes everything when the activation fails outright', () async {
      gateway.onActivate = () => throw StateError('cram refused');
      await expectLater(
          custody().onboard(atSign: _atSign, cram: 'cram'), throwsStateError);
      expectWiped();
    });

    test('a resumable handle keeps its keys until resume wipes them', () async {
      server.documentPutFailures = 3;
      late OnboardingIncompleteException incomplete;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        incomplete = e;
      }
      expect(derived.single.kek.any((b) => b != 0), isTrue);
      final session = await incomplete.pending.resume();
      expectWiped();
      await session.close();
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

    test('an unfinished activation hands its keys to the handle', () async {
      gateway.activationUnfinished = true;
      try {
        await custody().onboard(atSign: _atSign, cram: 'cram');
        fail('onboard completed');
      } on OnboardingIncompleteException catch (e) {
        expect(derived.single.authSeed.any((b) => b != 0), isTrue);
        await e.pending.abandon();
      }
      expectWiped();
    });
  });

  group('rotate', () {
    test('wipes the new passkey material and the closed session seed',
        () async {
      final current = await custody().enroll(atSign: _atSign, otp: _otp);
      forgetCaptured();
      final rotated = await custody().rotate(current, otp: _otp);
      expectWiped();
      expect(_zeroed(current.authSeed), isTrue);
      expect(_zeroed(rotated.authSeed), isFalse);
      await rotated.close();
      expect(_zeroed(rotated.authSeed), isTrue);
    });

    test('wipes everything when the new pointer does not read back', () async {
      final current = await custody().enroll(atSign: _atSign, otp: _otp);
      forgetCaptured();
      server.dropPointerWrites = true;
      await expectLater(custody().rotate(current, otp: _otp),
          throwsA(isA<RotationAbortedException>()));
      expectWiped();
      expect(_zeroed(current.authSeed), isFalse);
    });
  });
}
