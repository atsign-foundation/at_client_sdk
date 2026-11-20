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

/// The page environment with the capability probe pinned to "unknown" and the
/// clock set by the test.
class _PinnedEnvironment extends WebPrfEnvironment {
  _PinnedEnvironment(this.clock);

  DateTime clock;

  @override
  Future<bool?> clientCapabilityPrf() async => null;

  @override
  DateTime now() => clock;
}

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

class _Gateway extends Fake implements EnrollmentGateway {
  @override
  String get device => 'Test Device';
}

class _Hints extends Fake implements CredentialHintStore, EnrollmentIdStore {}

class _PointerReader extends Fake implements EnrollmentPointerReader {}

class _Deriver extends Fake implements PasskeyKeyDeriver {}

/// Every test that reads or writes the stored PRF miss lives in this suite:
/// browser suites share the page's local storage, and only tests in one
/// suite are run one at a time.
void main() {
  final start = DateTime.utc(2026, 11, 16, 12);

  setUp(() => window.localStorage.removeItem(_missKey));
  tearDown(() => window.localStorage.removeItem(_missKey));

  test('a recorded miss is read back from local storage', () {
    final env = WebPrfEnvironment();
    expect(env.missRecordedAt(), isNull);
    env.recordMiss(start);
    expect(env.missRecordedAt(), start);
    expect(window.localStorage.getItem(_missKey),
        start.millisecondsSinceEpoch.toString());
    expect(WebPrfEnvironment().missRecordedAt(), start);
  });

  test('a cleared miss reads as none', () {
    final env = WebPrfEnvironment();
    env.recordMiss(start);
    env.clearMiss();
    expect(env.missRecordedAt(), isNull);
    expect(window.localStorage.getItem(_missKey), isNull);
  });

  test('an unreadable stored value reads as no miss', () {
    window.localStorage.setItem(_missKey, 'not a number');
    expect(WebPrfEnvironment().missRecordedAt(), isNull);
  });

  test('the clock reads UTC', () {
    expect(WebPrfEnvironment().now().isUtc, isTrue);
  });

  group('the PRF capability probe', () {
    late JSAny? original;

    setUp(() => original = globalContext['PublicKeyCredential']);
    tearDown(() => globalContext['PublicKeyCredential'] = original);

    /// Replaces PublicKeyCredential with the object literal whose members are
    /// [body].
    void stubWith(String body) {
      final make = globalContext.callMethod<JSFunction>(
          'Function'.toJS, 'return {$body};'.toJS);
      globalContext['PublicKeyCredential'] = make.callAsFunction(null);
    }

    test('answers the extension:prf boolean the browser reports', () async {
      stubWith('getClientCapabilities() {'
          ' return Promise.resolve({"extension:prf": true}); }');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isTrue);
      stubWith('getClientCapabilities() {'
          ' return Promise.resolve({"extension:prf": false}); }');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isFalse);
    });

    test('is unknown when the capabilities name no extension:prf', () async {
      stubWith('getClientCapabilities() { return Promise.resolve({}); }');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isNull);
    });

    test('is unknown when extension:prf is not a boolean', () async {
      stubWith('getClientCapabilities() {'
          ' return Promise.resolve({"extension:prf": "yes"}); }');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isNull);
    });

    test('is unknown without getClientCapabilities', () async {
      stubWith('x: 1');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isNull);
    });

    test('is unknown when getClientCapabilities rejects', () async {
      stubWith('getClientCapabilities() {'
          ' return Promise.reject(new Error("no")); }');
      expect(await WebPrfEnvironment().clientCapabilityPrf(), isNull);
    });
  });

  group('PrfSupport over the page environment', () {
    test('supports PRF while no miss is recorded', () async {
      expect(await PrfSupport(_PinnedEnvironment(start)).supported(), isTrue);
    });

    test('records a miss stamped with the environment clock', () {
      PrfSupport(_PinnedEnvironment(start)).recordMiss();
      expect(WebPrfEnvironment().missRecordedAt(), start);
    });

    test('a recorded miss counts until the TTL passes on the clock', () async {
      final env = _PinnedEnvironment(start);
      final support = PrfSupport(env)..recordMiss();

      env.clock = start.add(prfMissTtl - const Duration(seconds: 1));
      expect(await support.supported(), isFalse);
      await expectLater(
          support.require(), throwsA(isA<PrfUnavailableException>()));

      env.clock = start.add(prfMissTtl);
      expect(await support.supported(), isTrue);
    });

    test('trying again clears the miss', () async {
      final support = PrfSupport(_PinnedEnvironment(start))..recordMiss();
      expect(await support.supported(), isFalse);
      support.tryAgain();
      expect(await support.supported(), isTrue);
      expect(WebPrfEnvironment().missRecordedAt(), isNull);
    });
  });

  group('a PRF miss recorded in the page', () {
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

    tearDown(() => globalContext['PublicKeyCredential'] = original);

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
  });
}
