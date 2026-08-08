import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

import 'utils/test_keys_dir.dart';

/// An [AtOnboardingService] binds to the enrollment it last authenticated as:
/// it holds an [AtLookUp] whose connection the atServer has bound to that
/// enrollment. The atServer refuses a `__manage` key fetch whose enrollment id
/// differs from the one the connection authenticated as, so an instance carried
/// from one enrollment into the next fetches keys it is not authorized to read.
///
/// Every test below therefore builds its own instances, and every
/// authentication gets a fresh one — see [authenticateWithApkamKeys].
void main() {
  String atSign = '@sitaram🛠';
  String masterKeysFilePath = testKeysFile(atSign);
  String apkamKeysFilePath = testKeysFile(atSign, suffix: 'apkam');
  String passwordProtectedKeysFilePath =
      testKeysFile(atSign, suffix: 'apkam-password-protected');
  String passPhrase = 'abcd';
  final logger = AtSignLogger('E2E Test');

  // Runs once before all tests.
  setUpAll(() async {
    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
        atSign,
        getOnboardingPreference(atSign, masterKeysFilePath)
          // Fetched cram key from the at_demos repo.
          ..cramSecret = cramKeyMap[atSign]);

    bool onboardingStatus = await onboardingService.onboard();
    expect(onboardingStatus, true);
    // Set SPP
    List<String> args = [
      'spp',
      '-s',
      'ABC123',
      '-a',
      atSign,
      '-r',
      'vip.ve.atsign.zone',
      '-k',
      masterKeysFilePath
    ];
    var res = await auth_cli.wrappedMain(args);
    // Zero indicates successful completion.
    expect(res, 0);
  });

  group('A group of tests to validate enrollment commands', () {
    /// The test verifies the following scenario's
    /// 1. Onboards an atSign
    /// 2. Sets Semi Permanent Passcode
    /// 3. Submits an enrollment request
    /// 4. Approves the enrollment request
    /// 5. Performs authentication with the approved enrollment Id. Authentication should be successful.
    /// 6. Revokes the enrollment Id.
    /// 7. Performs authentication again with the revoked enrollment Id. Authentication fails this time.
    /// 8. Unrevoke the enrollment Id.
    /// 9. Performs authentication again with the unrevoked enrollment Id. Authentication should be successful.
    test(
        'A test to verify end-to-end flow of approve revoke unrevoke of an enrollment',
        () async {
      AtOnboardingService enrollmentService = AtOnboardingServiceImpl(
          atSign, getOnboardingPreference(atSign, apkamKeysFilePath));

      // Submit enrollment request
      AtEnrollmentResponse atEnrollmentResponse = await enrollmentService
          .sendEnrollRequest(
              'wavi', 'local-device', 'ABC123', {'e2etest': 'rw'});
      String enrollmentId = atEnrollmentResponse.enrollmentId;
      logger.info(
          'Submitted enrollment successfully with enrollmentId: $enrollmentId');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(enrollmentId.isNotEmpty, true);

      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      var res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info('Approved enrollment with enrollmentId: $enrollmentId');

      // Generate Atkeys file for the enrollment request.
      await enrollmentService.awaitApproval(atEnrollmentResponse);
      await enrollmentService.createAtKeysFile(atEnrollmentResponse,
          atKeysFile: File(apkamKeysFilePath));

      // Authenticate with APKAM keys
      expect(
          await authenticateWithApkamKeys(
              atSign, apkamKeysFilePath, enrollmentId),
          true);

      // Revoke the enrollment
      args = [
        'revoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info('Revoked enrollment with enrollmentId: $enrollmentId');

      // Perform authentication with revoked enrollmentId.
      //
      // Polled with a bound rather than asserted immediate: for a short window
      // after a revoke, a holder of the revoked keyfile can still authenticate,
      // because the atServer resolves an enrollment's state for PKAM through a
      // cache that revocation reaches on an eventual schedule. The bound is
      // what keeps this an assertion — if the credential never stops working,
      // this stays red.
      bool revokedStillAuthenticates = true;
      for (var i = 0; i < 20; i++) {
        try {
          revokedStillAuthenticates = await authenticateWithApkamKeys(
              atSign, apkamKeysFilePath, enrollmentId);
        } on AtAuthenticationException {
          revokedStillAuthenticates = false;
        }
        if (!revokedStillAuthenticates) break;
        await Future<void>.delayed(Duration(milliseconds: 500));
      }
      expect(revokedStillAuthenticates, false,
          reason: 'a revoked enrollment must stop authenticating');

      // UnRevoke the enrollment
      args = [
        'unrevoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info('Un-Revoked enrollment with enrollmentId: $enrollmentId');

      // Perform authentication with the unrevoked enrollment-id.
      expect(
          await authenticateWithApkamKeys(
              atSign, apkamKeysFilePath, enrollmentId),
          true);
    });

    test('A test to verify password protected of atKeys file', () async {
      // The pass-phrase encrypts the atKeys file written upon approval of the
      // enrollment request.
      AtOnboardingService enrollmentService = AtOnboardingServiceImpl(
          atSign,
          getOnboardingPreference(atSign, passwordProtectedKeysFilePath)
            ..passPhrase = passPhrase
            ..hashingAlgoType = HashingAlgoType.argon2id);

      // Submit enrollment request
      AtEnrollmentResponse atEnrollmentResponse = await enrollmentService
          .sendEnrollRequest(
              'buzz', 'local-device', 'ABC123', {'e2etest': 'rw'});
      String enrollmentId = atEnrollmentResponse.enrollmentId;
      logger.info(
          'Submitted enrollment successfully with enrollmentId: $enrollmentId');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(enrollmentId.isNotEmpty, true);

      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        enrollmentId,
        '-k',
        masterKeysFilePath
      ];
      var res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info('Approved enrollment with enrollmentId: $enrollmentId');

      // Generate Atkeys file for the enrollment request.
      await enrollmentService.awaitApproval(atEnrollmentResponse);
      await enrollmentService.createAtKeysFile(atEnrollmentResponse,
          atKeysFile: File(passwordProtectedKeysFilePath));

      // Authenticate with APKAM keys
      expect(
          await authenticateWithApkamKeys(
              atSign, passwordProtectedKeysFilePath, enrollmentId,
              passPhrase: passPhrase,
              hashingAlgoType: HashingAlgoType.argon2id),
          true);

      // Run list to ensure the pass-phase is indeed working as expected
      args = [
        'list',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-P',
        passPhrase,
        '-k',
        passwordProtectedKeysFilePath
      ];
      res = await auth_cli.wrappedMain(args);
      // Zero indicate successful completion.
      expect(res, 0);
    });
  });

  tearDownAll(() {
    Directory('storage').deleteSync(recursive: true);
  });
}

/// Authenticates [atSign] as [enrollmentId] using the keys in
/// [atKeysFilePath], on an [AtOnboardingService] created for this call alone.
///
/// The instance is not returned or reused: authenticating binds it to
/// [enrollmentId], and reusing it for a different enrollment is what makes the
/// atServer refuse the next `__manage` key fetch.
Future<bool> authenticateWithApkamKeys(
    String atSign, String atKeysFilePath, String enrollmentId,
    {String? passPhrase, HashingAlgoType? hashingAlgoType}) async {
  AtOnboardingPreference preference =
      getOnboardingPreference(atSign, atKeysFilePath);
  if (passPhrase != null) {
    preference.passPhrase = passPhrase;
  }
  if (hashingAlgoType != null) {
    preference.hashingAlgoType = hashingAlgoType;
  }
  AtOnboardingService onboardingService =
      AtOnboardingServiceImpl(atSign, preference);
  return await onboardingService.authenticate(enrollmentId: enrollmentId);
}

AtOnboardingPreference getOnboardingPreference(
    String atSign, String atKeysFilePath) {
  atSign = AtUtils.fixAtSign(atSign);
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace = 'buzz'
    ..atKeysFilePath = atKeysFilePath
    ..appName = 'buzz'
    ..deviceName = 'iphone'
    ..rootDomain = 'vip.ve.atsign.zone';

  return atOnboardingPreference;
}
