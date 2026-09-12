import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

/// `Atsign.authenticatesAs`: one PKAM as the enrollment the keys name, the
/// id handed back, no client and no store.
void main() {
  const atSign = '@alice🛠';
  const rootDomain = AtRootDomain('127.0.0.1', 1);

  /// A legacy keyfile, enrolled as [enrollmentId] when one is given.
  AtKeys keysAs([String? enrollmentId]) => AtKeys()
    // ignore: deprecated_member_use
    ..apkamPublicKey = AtBytes.fromString(demo.pkamPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..apkamPrivateKey = AtBytes.fromString(demo.pkamPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPublicKey =
        AtBytes.fromString(demo.encryptionPublicKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultEncryptionPrivateKey =
        AtBytes.fromString(demo.encryptionPrivateKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..defaultSelfEncryptionKey = AtBytes.fromString(demo.aesKeyMap[atSign]!)
    // ignore: deprecated_member_use
    ..enrollmentId = enrollmentId;

  late MockAtLookupImpl lookUp;
  setUp(() {
    lookUp = MockAtLookupImpl();
    when(() => lookUp.close()).thenAnswer((_) async {});
  });

  test('answers with the enrollment the keys name, after one PKAM as it',
      () async {
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);

    final id = await Atsign(atSign).authenticatesAs(
        keys: InMemoryAtKeysIo.holding(atSign, keysAs('e-7')),
        rootDomain: rootDomain,
        atLookUp: lookUp);

    expect(id, 'e-7');
    verify(() => lookUp.pkamAuthenticate(enrollmentId: 'e-7')).called(1);
    verifyNever(() => lookUp.close());
    expect(AtClientImpl.holdsLiveClient(atSign), isFalse,
        reason: 'a check, not a client');
  });

  test('a keyfile that predates enrollments authenticates as primary',
      () async {
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);

    final id = await Atsign(atSign).authenticatesAs(
        keys: InMemoryAtKeysIo.holding(atSign, keysAs()),
        rootDomain: rootDomain,
        atLookUp: lookUp);

    // The raw literal: it is the id the atServer knows the atSign's own
    // credential by, and a keyfile naming no enrollment resolves to it.
    expect(id, 'primary');
    verify(() => lookUp.pkamAuthenticate(enrollmentId: 'primary')).called(1);
  });

  test('a refusal throws, naming the enrollment, and hands nothing back',
      () async {
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => false);

    await expectLater(
        () => Atsign(atSign).authenticatesAs(
            keys: InMemoryAtKeysIo.holding(atSign, keysAs('e-7')),
            rootDomain: rootDomain,
            atLookUp: lookUp),
        throwsA(isA<UnAuthenticatedException>()
            .having((e) => e.message, 'message', contains('as e-7'))));
    verifyNever(() => lookUp.close());
  });
}
