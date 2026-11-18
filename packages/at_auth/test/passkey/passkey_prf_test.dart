import 'dart:async';
import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

import '../support/passkey_fakes.dart';

final _at = DateTime.utc(2026, 11, 6, 14, 5);
const _device = 'Test Device';

void main() {
  final prf = Uint8List.fromList(List.generate(32, (i) => i));

  group('PasskeyPrf', () {
    test('signalUnknownCredential tells a port that can hear it', () async {
      final port = _SignallingPort();
      final id = Uint8List.fromList([9, 9]);
      await PasskeyPrf(port).signalUnknownCredential(id);
      expect(port.signalled, [id]);
    });

    test('signalUnknownCredential does nothing for a port without the signal',
        () async {
      await PasskeyPrf(FakePasskeyPort())
          .signalUnknownCredential(Uint8List.fromList([1]));
    });

    test('signalUnknownCredential swallows a failing signal', () async {
      final port = _SignallingPort()..fails = true;
      await PasskeyPrf(port).signalUnknownCredential(Uint8List.fromList([1]));
      expect(port.signalled, hasLength(1));
    });

    test('register creates, then reads the PRF from a get with the salt',
        () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      final result = await PasskeyPrf(port)
          .register('@alice', enrolledAt: _at, deviceName: _device);
      expect(port.calls, ['create', 'get']);
      expect(port.lastGetAllowCredential, port.resultCredentialId);
      expect(result.credentialId, port.resultCredentialId);
      expect(result.secret.output, prf);
    });

    test('unlock returns the PrfSecret and narrows by credentialId', () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      final credId = Uint8List.fromList([4, 5, 6]);
      final result = await PasskeyPrf(port).unlock(credentialId: credId);
      expect(port.lastGetAllowCredential, credId);
      expect(result.secret.output, prf);
    });

    test('unlock and register evaluate the PRF over the record salt', () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await PasskeyPrf(port).unlock();
      expect(port.lastGetEvalInput, recordPrfSalt());
      port.lastGetEvalInput = null;
      await PasskeyPrf(port)
          .register('@alice', enrolledAt: _at, deviceName: _device);
      expect(port.lastGetEvalInput, recordPrfSalt());
    });

    test('register names the passkey for the canonical atSign', () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await PasskeyPrf(port)
          .register('Ali.ce', enrolledAt: _at, deviceName: _device);
      expect(port.lastCreateAtSign, '@alice');
    });

    test('register hands the enrollment time and device name to the port',
        () async {
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await PasskeyPrf(port)
          .register('@alice', enrolledAt: _at, deviceName: _device);
      expect(port.lastCreateEnrolledAt, _at);
      expect(port.lastCreateDeviceName, _device);
    });

    test('unlock without a credentialId asks for any discoverable passkey',
        () async {
      final port = FakePasskeyPort()
        ..resultPrfFirst = prf
        ..lastGetAllowCredential = Uint8List.fromList([9]);
      await PasskeyPrf(port).unlock();
      expect(port.calls, ['get']);
      expect(port.lastGetAllowCredential, isNull);
    });

    test('a null or 31-byte PRF is PrfUnavailableException', () async {
      final port = FakePasskeyPort()..resultPrfFirst = null;
      await expectLater(
          PasskeyPrf(port).unlock(), throwsA(isA<PrfUnavailableException>()));
      port.resultPrfFirst = Uint8List(31);
      await expectLater(
          PasskeyPrf(port)
              .register('@alice', enrolledAt: _at, deviceName: _device),
          throwsA(isA<PrfUnavailableException>()));
    });

    test('a 31-byte PRF output is zeroed before it is refused', () async {
      final short = Uint8List.fromList(List.filled(31, 9));
      final port = FakePasskeyPort()..resultPrfFirst = short;
      await expectLater(
          PasskeyPrf(port).unlock(), throwsA(isA<PrfUnavailableException>()));
      expect(short, everyElement(0));
    });

    test('a PRF output of 32 zero bytes is PrfUnavailableException', () async {
      final port = FakePasskeyPort()..resultPrfFirst = Uint8List(32);
      await expectLater(
          PasskeyPrf(port).unlock(), throwsA(isA<PrfUnavailableException>()));
      await expectLater(
          PasskeyPrf(port)
              .register('@alice', enrolledAt: _at, deviceName: _device),
          throwsA(isA<PrfUnavailableException>()));
    });

    for (final (output, bytes) in [
      ('no', null),
      ('a 31-byte', Uint8List.fromList(List.filled(31, 1))),
      ('an all-zero', Uint8List(32)),
    ]) {
      test('$output PRF output is refused with one plain message', () async {
        final port = FakePasskeyPort()..resultPrfFirst = bytes;
        await expectLater(
            PasskeyPrf(port).unlock(),
            throwsA(isA<PrfUnavailableException>().having(
                (e) => e.message,
                'message',
                'The authenticator did not return a usable PRF result')));
      });
    }

    test('register refuses before any ceremony when PRF is unsupported',
        () async {
      final env = FakePrfEnvironment()..capability = false;
      final port = FakePasskeyPort()..resultPrfFirst = prf;
      await expectLater(
          PasskeyPrf(port, prfSupport: PrfSupport(env))
              .register('@alice', enrolledAt: _at, deviceName: _device),
          throwsA(isA<PrfUnavailableException>()));
      expect(port.calls, isEmpty);
    });
  });

  group('the PRF-miss flag is set only on a definite no', () {
    late FakePrfEnvironment env;
    late FakePasskeyPort port;
    late PasskeyPrf passkeys;

    setUp(() {
      env = FakePrfEnvironment();
      port = FakePasskeyPort()..resultPrfFirst = prf;
      passkeys = PasskeyPrf(port, prfSupport: PrfSupport(env));
    });

    Future<PasskeyRegistration> register() =>
        passkeys.register('@alice', enrolledAt: _at, deviceName: _device);

    test(
        'create without PRF enabled and a PRF-less get sets it whatever the '
        'capability says', () async {
      for (final capability in [null, true]) {
        for (final enabled in [null, false]) {
          env = FakePrfEnvironment()..capability = capability;
          port = FakePasskeyPort()
            ..createPrfEnabled = enabled
            ..resultPrfFirst = null;
          passkeys = PasskeyPrf(port, prfSupport: PrfSupport(env));
          await expectLater(register(), throwsA(isA<PrfUnavailableException>()),
              reason: '$capability/$enabled');
          expect(env.missAt, env.clock, reason: '$capability/$enabled');
        }
      }
    });

    test('create with PRF enabled and a PRF-less get does not', () async {
      port
        ..createPrfEnabled = true
        ..resultPrfFirst = null;
      await expectLater(register(), throwsA(isA<PrfUnavailableException>()));
      expect(env.missAt, isNull);
    });

    test('create without PRF enabled but a get that returns PRF does not',
        () async {
      port.createPrfEnabled = false;
      final result = await register();
      expect(result.secret.output, prf);
      expect(env.missAt, isNull);
    });

    test('a PRF-less unlock does not', () async {
      port.resultPrfFirst = null;
      await expectLater(
          passkeys.unlock(), throwsA(isA<PrfUnavailableException>()));
      expect(env.missAt, isNull);
    });

    for (final failure in [
      PasskeyCeremonyException('cancelled'),
      PasskeyCeremonyException('timed out'),
      StateError('port blew up'),
    ]) {
      test('${failure.runtimeType} ($failure) during register does not',
          () async {
        port.failure = failure;
        await expectLater(register(), throwsA(same(failure)));
        expect(env.missAt, isNull);
      });

      test('${failure.runtimeType} ($failure) during unlock does not',
          () async {
        port.failure = failure;
        await expectLater(passkeys.unlock(), throwsA(same(failure)));
        expect(env.missAt, isNull);
      });
    }

    test('a failed get after a successful create does not', () async {
      port.failure = null;
      final failing = _FailsOnGet(port);
      await expectLater(
          PasskeyPrf(failing, prfSupport: PrfSupport(env))
              .register('@alice', enrolledAt: _at, deviceName: _device),
          throwsA(isA<PasskeyCeremonyException>()));
      expect(env.missAt, isNull);
    });

    test('try again clears a recorded miss and the ceremony runs', () async {
      env.missAt = env.clock;
      final support = PrfSupport(env);
      expect(await support.supported(), isFalse);
      support.tryAgain();
      expect(env.missAt, isNull);
      expect(await support.supported(), isTrue);
      await PasskeyPrf(port, prfSupport: support)
          .register('@alice', enrolledAt: _at, deviceName: _device);
      expect(port.calls, ['create', 'get']);
    });

    test('try again with no recorded miss is a no-op', () async {
      final support = PrfSupport(env)..tryAgain();
      expect(env.missAt, isNull);
      expect(await support.supported(), isTrue);
    });
  });

  group('a registered passkey without a usable PRF output', () {
    late _SignallingPort port;

    setUp(() => port = _SignallingPort()..resultPrfFirst = prf);

    Future<PasskeyRegistration> register() => PasskeyPrf(port)
        .register('@alice', enrolledAt: _at, deviceName: _device);

    for (final (outcome, fail, failure) in [
      (
        'an assertion that throws',
        (_SignallingPort p) => p.getFailure = PasskeyCeremonyException('x'),
        isA<PasskeyCeremonyException>()
      ),
      (
        'an assertion with no PRF output',
        (_SignallingPort p) => p.resultPrfFirst = null,
        isA<PrfUnavailableException>()
      ),
      (
        'an assertion with a 31-byte PRF output',
        (_SignallingPort p) =>
            p.resultPrfFirst = Uint8List.fromList(List.filled(31, 1)),
        isA<PrfUnavailableException>()
      ),
      (
        'an assertion with 32 zero bytes',
        (_SignallingPort p) => p.resultPrfFirst = Uint8List(32),
        isA<PrfUnavailableException>()
      ),
    ]) {
      test('is reported as unknown after $outcome', () async {
        fail(port);
        await expectLater(register(), throwsA(failure));
        expect(port.calls, ['create', 'get']);
        expect(port.signalled, [port.resultCredentialId]);
      });
    }

    test('a usable PRF output reports nothing', () async {
      await register();
      expect(port.signalled, isEmpty);
    });

    test('a failed create reports nothing', () async {
      port.failure = PasskeyCeremonyException('x');
      await expectLater(register(), throwsA(isA<PasskeyCeremonyException>()));
      expect(port.calls, ['create']);
      expect(port.signalled, isEmpty);
    });

    test('a refused report leaves the registration failure as it was',
        () async {
      final cancelled = PasskeyCeremonyException('cancelled');
      port
        ..fails = true
        ..getFailure = cancelled;
      await expectLater(register(), throwsA(same(cancelled)));
      expect(port.signalled, hasLength(1));
    });

    test('a report the platform never answers does not hold back the failure',
        () async {
      port
        ..unanswered = Completer<void>()
        ..resultPrfFirst = null;
      Object? failure;
      unawaited(register().then<void>((_) {}, onError: (Object e) {
        failure = e;
      }));
      await pumpEventQueue();
      expect(port.signalled, [port.resultCredentialId]);
      expect(failure, isA<PrfUnavailableException>());
    });
  });
}

class _FailsOnGet implements PasskeyPort {
  _FailsOnGet(this.inner);
  final PasskeyPort inner;

  @override
  Future<PasskeyCreation> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) =>
      inner.create(
          atSign: atSign, enrolledAt: enrolledAt, deviceName: deviceName);

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      throw PasskeyCeremonyException('cancelled');
}

/// A port that can also tell the platform a credential is unknown.
class _SignallingPort extends FakePasskeyPort
    implements UnknownCredentialSignal {
  final signalled = <Uint8List>[];
  var fails = false;

  /// When set, the assertion alone throws it.
  Object? getFailure;

  /// When set, a report waits on it, as a platform that never answers does.
  Completer<void>? unanswered;

  @override
  Future<PasskeyAssertion> get(
      {required Uint8List evalInput, Uint8List? allowCredential}) async {
    if (getFailure case final failure?) {
      calls.add('get');
      throw failure;
    }
    return super.get(evalInput: evalInput, allowCredential: allowCredential);
  }

  @override
  Future<void> signalUnknownCredential(Uint8List credentialId) async {
    signalled.add(credentialId);
    if (fails) throw StateError('platform refused');
    await unanswered?.future;
  }
}
