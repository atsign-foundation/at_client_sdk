import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/enroll/at_enrollment_impl.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtLookUp extends Mock implements AtLookupImpl {}

/// What one poll of the approval handshake runs into.
enum Poll {
  /// The atServer answered: this enrollment has not been decided yet.
  pending,

  /// The atServer could not be reached at all.
  unreachable,

  /// The atServer answered: PKAM succeeded, so the enrollment was approved.
  approved,
}

void main() {
  const atSign = '@alice🛠';

  /// A handshake rig whose PKAM polls run into [script], one entry per poll,
  /// and whose post-approval key fetches succeed — so the only thing under
  /// observation is how the retry budget responds to the script.
  Future<(AtEnrollmentResponse, MockAtLookUp, List<Poll>)> rig(
      List<Poll> script) async {
    final apkamSymmetricKey = apkamSymmetricKeyMap[atSign]!;
    final encryptionPrivateKey = encryptionPrivateKeyMap[atSign]!;
    final selfEncryptionKey = aesKeyMap[atSign]!;

    final atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
            encryptionPublicKeyMap[atSign]!, encryptionPrivateKey),
        AtPkamKeyPair.create(
            pkamPublicKeyMap[atSign]!, pkamPrivateKeyMap[atSign]!));
    atChopsKeys.apkamSymmetricKey = AESKey(apkamSymmetricKey);
    final atChopsImpl = AtChopsImpl(atChopsKeys);
    final iv = AtChopsUtil.generateIVLegacy();

    Future<String> sealed(String value) async => (await atChopsImpl
            .encryptString(value, EncryptionKeyType.aes256,
                keyName: 'apkamSymmetricKey', iv: iv))
        .result;

    final sealedPrivateKey = await sealed(encryptionPrivateKey);
    final sealedSelfKey = await sealed(selfEncryptionKey);

    final polled = <Poll>[];
    final lookup = MockAtLookUp();
    when(() => lookup.pkamAuthenticate(enrollmentId: '123'))
        .thenAnswer((_) async {
      final outcome =
          polled.length < script.length ? script[polled.length] : Poll.approved;
      polled.add(outcome);
      switch (outcome) {
        case Poll.pending:
          throw UnAuthenticatedException('error:AT0401 enrollment is pending');
        case Poll.unreachable:
          throw AtLookUpException('AT0021', 'the atServer is unreachable');
        case Poll.approved:
          return true;
      }
    });
    when(() => lookup.executeCommand(
            any(
                that: startsWith(
                    'keys:get:keyName:123.default_enc_private_key')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:${jsonEncode({'value': sealedPrivateKey})}');
    when(() => lookup.executeCommand(
            any(that: startsWith('keys:get:keyName:123.default_self_enc_key')),
            auth: any(named: 'auth')))
        .thenAnswer(
            (_) async => 'data:${jsonEncode({'value': sealedSelfKey})}');

    final keys = AtKeys()
      ..apkamPublicKey = AtBytes.fromString(pkamPublicKeyMap[atSign]!)
      ..apkamPrivateKey = AtBytes.fromString(pkamPrivateKeyMap[atSign]!)
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(encryptionPublicKeyMap[atSign]!)
      ..apkamSymmetricKey = AtBytes.fromString(apkamSymmetricKey);

    final response = AtEnrollmentResponse('123', EnrollmentStatus.pending,
        atSign: atSign,
        rootDomain: AtRootDomain.atsignDomain,
        atAuthKeys: keys);
    return (response, lookup, polled);
  }

  Future<void> waitFor(
          AtEnrollmentResponse response, MockAtLookUp lookup, int maxRetries) =>
      AtEnrollmentImpl().waitForApproval(response,
          atLookup: lookup,
          maxRetries: maxRetries,
          retryInterval: const Duration(milliseconds: 1),
          logProgress: false);

  group('the retry budget', () {
    test('is never spent by an enrollment nobody has decided yet', () async {
      // Whoever approves this does so on their own schedule, so a pending
      // answer is not a failure and a wait for one is deliberately unbounded.
      final script = List.filled(20, Poll.pending);
      final (response, lookup, polled) = await rig(script);

      await waitFor(response, lookup, 2);

      expect(polled.length, 21,
          reason: 'twenty pending polls against a budget of two, and the '
              'twenty-first poll is the one that found it approved');
    });

    test('survives more unreachable polls than the budget, spread out',
        () async {
      // Two failures, an answer, two more, an answer, two more: six failures
      // against a budget of two, but never three in a row. Reaching the
      // atServer is what the budget measures, so each answer restores it.
      final (response, lookup, polled) = await rig([
        Poll.unreachable,
        Poll.unreachable,
        Poll.pending,
        Poll.unreachable,
        Poll.unreachable,
        Poll.pending,
        Poll.unreachable,
        Poll.unreachable,
        Poll.approved,
      ]);

      await waitFor(response, lookup, 2);

      expect(polled.where((p) => p == Poll.unreachable).length, 6,
          reason: 'the wait rode out every one of them');
      expect(response.atAuthKeys!.defaultEncryptionPrivateKey!.toString(),
          encryptionPrivateKeyMap[atSign]!);
    });

    test('is exhausted by consecutive unreachable polls', () async {
      // The escape hatch from an atServer that is genuinely gone: one more
      // consecutive failure than the budget allows, and the cause propagates
      // rather than being swallowed into another retry.
      final (response, lookup, polled) = await rig(List.filled(9, Poll.unreachable));

      await expectLater(
          waitFor(response, lookup, 2), throwsA(isA<AtLookUpException>()));

      expect(polled.length, 3,
          reason: 'two failures tolerated, the third fatal');
    });
  });
}
