import 'dart:typed_data';

import 'package:at_auth/passkey.dart';
import 'package:test/test.dart';

class _Port implements PasskeyPort {
  @override
  Future<PasskeyCreation> create(
          {required String atSign,
          required DateTime enrolledAt,
          required String deviceName}) async =>
      (credentialId: Uint8List(1), prfEnabled: true);

  @override
  Future<PasskeyAssertion> get(
          {required Uint8List evalInput, Uint8List? allowCredential}) async =>
      (
        credentialId: Uint8List(1),
        prfFirst: Uint8List(32)..fillRange(0, 32, 9)
      );
}

class _Env implements PrfEnvironment {
  DateTime? missAt;
  @override
  Future<bool?> clientCapabilityPrf() async => null;
  @override
  DateTime? missRecordedAt() => missAt;
  @override
  void recordMiss(DateTime at) => missAt = at;
  @override
  void clearMiss() => missAt = null;
  @override
  DateTime now() => DateTime.utc(2026, 1, 1);
}

class _Sealer implements RecordSealer {
  @override
  Future<Uint8List> seal(Uint8List iv, List<int> plaintext, List<int> aad) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> open(Uint8List iv, Uint8List ciphertext, List<int> aad) =>
      throw UnimplementedError();
  @override
  void close() {}
}

class _Deriver implements PasskeyKeyDeriver {
  @override
  Future<PasskeyDerivation> derive(PrfSecret prf, String atSign) async => (
        lookupHex: 'a' * 64,
        ns: 'b' * 64,
        authSeed: Uint8List(32),
        sealer: _Sealer(),
      );
}

class _Lock implements SetupLock {
  @override
  Future<T> run<T>(String name, Future<T> Function() body) => body();
}

class _Hints implements PasskeyHintStore {
  Uint8List? credential;
  String? enrollment;
  @override
  Future<Uint8List?> credentialId(String atSign) async => credential;
  @override
  Future<String?> enrollmentId(String atSign) async => enrollment;
  @override
  Future<void> putHint(
      String atSign, Uint8List credentialId, String enrollmentId) async {
    credential = credentialId;
    enrollment = enrollmentId;
  }
}

void main() {
  // Each test uses an exported symbol, so a removed or renamed export fails to
  // compile and a changed one fails the assertion.
  test('record types, labels and the PRF salt', () async {
    expect(PasskeyRecordType.values, isNotEmpty);
    expect(recordIdLabel, isNotEmpty);
    expect(recordNsLabel, isNotEmpty);
    expect(recordSealLabel, isNotEmpty);
    expect(recordAuthSeedLabel, isNotEmpty);
    expect(recordPrfSalt().length, 32);
  });

  test('passkeyDisplayName and passkeyDisplayNameMaxBytes', () {
    expect(passkeyDisplayName(DateTime.utc(2026), 'd'), isNotEmpty);
    expect(passkeyDisplayNameMaxBytes, 64);
  });

  test('exceptions', () {
    expect(PasskeyCeremonyException('x').message, 'x');
    expect(PrfUnavailableException('x').message, 'x');
    expect(UnsupportedPasskeyRecordException('x').message, 'x');
    expect(PasskeyRecordAuthenticationException().message, isNotEmpty);
  });

  test('PasskeyHintStore reads each id and writes the pair together', () async {
    final PasskeyHintStore store = _Hints();
    await store.putHint('@a', Uint8List.fromList([1]), 'e1');
    expect(await store.credentialId('@a'), [1]);
    expect(await store.enrollmentId('@a'), 'e1');
  });

  test('PrfSecret wipes its output', () {
    final bytes = Uint8List(32)..fillRange(0, 32, 1);
    PrfSecret(bytes).wipe();
    expect(bytes, everyElement(0));
  });

  test('PrfSupport, PrfEnvironment, prfMissTtl and prfUnsupportedMessage',
      () async {
    final env = _Env();
    final support = PrfSupport(env);
    expect(await support.supported(), isTrue);
    support.recordMiss();
    expect(await support.supported(), isFalse);
    await expectLater(
        support.require(),
        throwsA(isA<PrfUnavailableException>()
            .having((e) => e.message, 'message', prfUnsupportedMessage)));
    expect(prfMissTtl, const Duration(days: 30));
    support.tryAgain();
    expect(await support.supported(), isTrue);
  });

  test(
      'PasskeyPrf, PasskeyPort, PasskeyCreation, PasskeyAssertion, '
      'PasskeyRegistration and PasskeyUnlock', () async {
    final PasskeyPort port = _Port();
    final PasskeyCreation creation = await port.create(
        atSign: '@alice', enrolledAt: DateTime.utc(2026), deviceName: 'd');
    expect(creation.prfEnabled, isTrue);
    final PasskeyAssertion assertion = await port.get(evalInput: Uint8List(32));
    expect(assertion.prfFirst, isNotNull);

    final prf = PasskeyPrf(port);
    final PasskeyRegistration registration = await prf.register('@alice',
        enrolledAt: DateTime.utc(2026), deviceName: 'd');
    expect(registration.secret.output.length, 32);
    final PasskeyUnlock unlock = await prf.unlock();
    expect(unlock.credentialId, isNotEmpty);
  });

  test('PasskeyVault, PasskeyDerivation, PasskeyKeyDeriver and RecordSealer',
      () async {
    final PasskeyKeyDeriver deriver = _Deriver();
    final PasskeyDerivation derivation =
        await deriver.derive(PrfSecret(Uint8List(32)..[0] = 1), '@alice');
    final RecordSealer sealer = derivation.sealer;
    final vault = PasskeyVault(derivation, atSign: '@alice');
    expect(vault.lookupHex, 'a' * 64);
    expect(vault.ns, 'b' * 64);
    vault.close();
    await expectLater(
        vault.withAuthSeed((_) async => 1), throwsA(isA<StateError>()));
    expect(sealer, isNotNull);
  });

  test('PasskeyRecordCodec rejects a record of unknown shape', () async {
    await expectLater(
        PasskeyRecordCodec.open(
            _Sealer(), '@alice', PasskeyRecordType.atkeys, '{"v":99}'),
        throwsA(isA<UnsupportedPasskeyRecordException>()));
  });

  test('SetupLock, setupLockName and the stores', () async {
    expect(setupLockName('app:setup', '@alice'), 'app:setup:@alice');
    expect(await _Lock().run('n', () async => 5), 5);
    expect(await _Hints().credentialId('@alice'), isNull);
    expect(await _Hints().enrollmentId('@alice'), isNull);
  });
}
