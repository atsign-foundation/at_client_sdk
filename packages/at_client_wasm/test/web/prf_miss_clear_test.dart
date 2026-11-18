@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:at_client/passkey.dart';
import 'package:at_client_wasm/at_client_wasm_web.dart' show clearPrfMiss;
import 'package:at_client_wasm/src/keys/web_prf_environment.dart';
import 'package:test/fake.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

const _missKey = 'at_client_wasm:prf-miss-at';

/// An authenticator whose create succeeds and whose assertion is cancelled,
/// so an onboarding stops right after the create ceremony.
class _Authenticator implements PasskeyPort {
  var creates = 0;

  @override
  Future<PasskeyCreation> create(
      {required String atSign,
      required DateTime enrolledAt,
      required String deviceName}) async {
    creates++;
    return (credentialId: Uint8List.fromList([1]), prfEnabled: true);
  }

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      throw PasskeyCeremonyException('NotAllowedError');
}

class _Lock implements SetupLock {
  @override
  Future<T> run<T>(String name, Future<T> Function() body) => body();
}

class _NoPendingRecord extends Fake implements PendingOnboardingStore {
  @override
  Future<PendingOnboardingRecord?> get(String atSign) async => null;
}

class _Gateway extends Fake implements EnrollmentGateway {
  @override
  String get device => 'Test Device';
}

class _Hints extends Fake implements CredentialHintStore, EnrollmentIdStore {}

class _PointerReader extends Fake implements EnrollmentPointerReader {}

class _Deriver extends Fake implements PasskeyKeyDeriver {}

void main() {
  late JSAny? original;
  late _Authenticator authenticator;

  PasskeyCustody custody() {
    final hints = _Hints();
    return PasskeyCustody(
        prf: PasskeyPrf(authenticator,
            prfSupport: PrfSupport(WebPrfEnvironment())),
        pointerReader: _PointerReader(),
        gateway: _Gateway(),
        credentials: hints,
        enrollmentIds: hints,
        pendingStore: _NoPendingRecord(),
        setupLock: _Lock(),
        setupLockPrefix: 'test:setup',
        deriver: _Deriver());
  }

  setUp(() {
    original = globalContext['PublicKeyCredential'];
    globalContext['PublicKeyCredential'] = JSObject();
    authenticator = _Authenticator();
    WebPrfEnvironment().recordMiss(DateTime.now().toUtc());
  });

  tearDown(() {
    globalContext['PublicKeyCredential'] = original;
    window.localStorage.removeItem(_missKey);
  });

  test('a recorded PRF miss refuses onboarding before the create ceremony',
      () async {
    await expectLater(custody().onboard(atSign: '@alice🛠', cram: 'cram'),
        throwsA(isA<PrfUnavailableException>()));
    expect(authenticator.creates, 0);
  });

  test(
      'An app clears a recorded PRF miss, and onboarding tries the passkey '
      'again', () async {
    clearPrfMiss();
    await expectLater(custody().onboard(atSign: '@alice🛠', cram: 'cram'),
        throwsA(isA<PasskeyCeremonyException>()));
    expect(authenticator.creates, 1);
  });
}
