import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/enrollment_approver.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_demo_data/at_demo_data.dart' as demo;
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookUp {}

/// Approval needs the atSign's encryption private key and its self-encryption
/// key. Neither is authentication, and neither should have to come from a
/// network object. These pin that the approver can work with its own crypto
/// and an at_lookup holding none - which is the world step 5 creates when it
/// deletes `AtLookUp.atChops`.
void main() {
  const atSign = '@alice🛠';

  AtChops approverChops() => AtChopsImpl(AtChopsKeys.create(
      AtEncryptionKeyPair.create(
          demo.encryptionPublicKeyMap[atSign]!, demo.encryptionPrivateKeyMap[atSign]!),
      AtPkamKeyPair.create(
          demo.pkamPublicKeyMap[atSign]!, demo.pkamPrivateKeyMap[atSign]!))
    ..selfEncryptionKey = AESKey(demo.aesKeyMap[atSign]!));

  EnrollmentRequestDecision decision() =>
      EnrollmentRequestDecision.approvedWithMintedKey(
        enrollmentId: 'abc-123',
        apkamSymmetricKey: demo.aesKeyMap[atSign]!,
        atSign: atSign,
      );

  test('an approver given its own chops does not need the lookup to hold any',
      () async {
    final lookUp = MockAtLookUp();
    when(() => lookUp.atChops).thenReturn(null);
    when(() => lookUp.executeCommand(any(), auth: any(named: 'auth')))
        .thenAnswer((_) async =>
            'data:{"enrollmentId":"abc-123","status":"approved"}');

    final response = await EnrollmentApprover()
        .approve(decision(), lookUp, approverChops: approverChops());

    expect(response.enrollmentId, 'abc-123');
    // Never even asked. The fallback is `approverChops ?? atLookUp.atChops`,
    // so supplying one short-circuits it - which is what lets step 5 delete
    // the field without this method noticing.
    verifyNever(() => lookUp.atChops);
  });

  test('and with neither, it still refuses', () async {
    // The control. If this passed too, the test above would say nothing about
    // where the crypto came from.
    final lookUp = MockAtLookUp();
    when(() => lookUp.atChops).thenReturn(null);

    await expectLater(
        () => EnrollmentApprover().approve(decision(), lookUp),
        throwsA(predicate((dynamic e) =>
            e is AtAuthenticationException &&
            e.message.contains('authentication keys are not initialized'))));
  });
}
