import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../test_utils/mocks.dart';

/// `Atsign.authenticatesAs`: one PKAM as the enrollment the keys name, the
/// id handed back, no client and no store. The keys decide which
/// enrollment: the one holding active typed material, else the flat stored
/// id, else `primary`.
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
    when(() =>
            lookUp.pkamAuthenticate(enrollmentId: any(named: 'enrollmentId')))
        .thenAnswer((_) async => true);
  });

  /// The enrollment id that reached the PKAM, which is what signs the
  /// challenge, rather than what the document says.
  Future<String?> idReachingPkam(AtKeysIo keys) async {
    await Atsign(atSign)
        .authenticatesAs(keys: keys, rootDomain: rootDomain, atLookUp: lookUp);
    return verify(() => lookUp.pkamAuthenticate(
            enrollmentId: captureAny(named: 'enrollmentId'))).captured.single
        as String?;
  }

  /// A retrofitted keyfile: the flat fields keep the legacy enrollment's
  /// credentials, the typed section carries the successor's. The one shape
  /// where "the flat id" and "the derived id" are both real and differ.
  Future<InMemoryAtKeysIo> retrofittedKeyfile() async {
    final keysIo = InMemoryAtKeysIo.holding(atSign, keysAs('legacy-1'));

    // Retrofit it for real rather than hand-building the end state: a
    // hand-assembled document is a claim about what a retrofit produces, and
    // this test is about what the keys resolve to afterwards.
    final approving = MockAtLookupImpl();
    when(() => approving.executeCommand(any(that: startsWith('enroll:')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:{"enrollmentId":"new-123","status":"approved"}');
    await AtEnrollment.create().submit(
        AtSelfEnrollmentRequest(
            session: AtAuthSession(
                atSign: atSign,
                rootDomain: rootDomain,
                atKeysIo: keysIo,
                enrollmentId: 'legacy-1'),
            appName: 'selfapp',
            deviceName: 'selfdevice',
            namespaces: {'app_1': 'rw'}),
        approving);

    // NOTE: the two sources must disagree, or the test below passes for a
    // reason that has nothing to do with which one the keys resolved.
    final retrofitted = await keysIo.read(atSign);
    // ignore: deprecated_member_use
    expect(retrofitted.enrollmentId, 'legacy-1');
    expect(retrofitted.resolveAuthenticatingEnrollment(), 'new-123',
        reason: 'the two sources must give different, non-null answers or '
            'this fixture discriminates nothing');
    return keysIo;
  }

  test('answers with the enrollment the keys name, after one PKAM as it',
      () async {
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

  test('a legacy keyfile authenticates as its flat stored enrollment',
      () async {
    final keys = keysAs('flat-1');
    expect(keys.resolveAuthenticatingEnrollment(), isNull,
        reason: 'the fixture holds no typed authentication material, so the '
            'id that reaches pkam can only have come from the flat field');
    expect(
        await idReachingPkam(InMemoryAtKeysIo.holding(atSign, keys)), 'flat-1');
  });

  test(
      'a RETROFITTED keyfile authenticates as the successor, not the flat '
      'legacy enrollment', () async {
    expect(await idReachingPkam(await retrofittedKeyfile()), 'new-123',
        reason: 'the retrofit exists to move the client to its successor; '
            'the flat field still names legacy-1, and reading it would sign '
            'the PKAM challenge as the enrollment the successor replaced');
  });

  test('an ancient keyfile with no enrollment id authenticates as primary',
      () async {
    // For a keyfile with no stored id, `primary` is the atServer's name for
    // that credential; the verb builder keeps it off the wire. The raw
    // literal, since it is the id the atServer knows the credential by.
    final id = await Atsign(atSign).authenticatesAs(
        keys: InMemoryAtKeysIo.holding(atSign, keysAs()),
        rootDomain: rootDomain,
        atLookUp: lookUp);

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
