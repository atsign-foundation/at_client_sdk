import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_demo_data/at_demo_data.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;
import 'package:at_utils/at_utils.dart';
import 'package:test/test.dart';

void main() {
  String atSign = '@sitaram🛠';
  String apkamKeysFilePath = 'storage/keys/@sitaram-apkam.atKeys';
  final logger = AtSignLogger('E2E Test');
  late AtOnboardingService atOnboardingService;

  // Runs once before all tests.
  setUpAll(() async {
    atOnboardingService = AtOnboardingServiceImpl(
        atSign,
        getOnboardingPreference(atSign,
            '${Platform.environment['HOME']}/.atsign/keys/${atSign}_key.atKeys')
          // Fetched cram key from the at_demos repo.
          ..cramSecret = cramKeyMap[atSign]);

    bool onboardingStatus = await atOnboardingService.onboard();
    expect(onboardingStatus, true);
    // Set SPP
    List<String> args = [
      'spp',
      '-s',
      'ABC123',
      '-a',
      atSign,
      '-r',
      'vip.ve.atsign.zone'
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
      // Submit enrollment request
      AtEnrollmentResponse atEnrollmentResponse = await atOnboardingService
          .sendEnrollRequest(
              'wavi', 'local-device', 'ABC123', {'e2etest': 'rw'});
      logger.info(
          'Submitted enrollment successfully with enrollmentId: ${atEnrollmentResponse.enrollmentId}');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(atEnrollmentResponse.enrollmentId.isNotEmpty, true);

      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        atEnrollmentResponse.enrollmentId
      ];
      var res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info(
          'Approved enrollment with enrollmentId: ${atEnrollmentResponse.enrollmentId}');

      // Generate Atkeys file for the enrollment request.
      await atOnboardingService.awaitApproval(atEnrollmentResponse);
      await atOnboardingService.createAtKeysFile(atEnrollmentResponse,
          atKeysFile: File(apkamKeysFilePath));

      // Authenticate with APKAM keys
      atOnboardingService = AtOnboardingServiceImpl(
          atSign, getOnboardingPreference(atSign, apkamKeysFilePath));
      bool authResponse = await atOnboardingService.authenticate(
          enrollmentId: atEnrollmentResponse.enrollmentId);
      expect(authResponse, true);

      // Revoke the enrollment
      args = [
        'revoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        atEnrollmentResponse.enrollmentId
      ];
      res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info(
          'Revoked enrollment with enrollmentId: ${atEnrollmentResponse.enrollmentId}');

      // Perform authentication with revoked enrollmentId
      expect(
          () async => await atOnboardingService.authenticate(
              enrollmentId: atEnrollmentResponse.enrollmentId),
          throwsA(predicate((dynamic e) => e is AtAuthenticationException)));

      // UnRevoke the enrollment
      args = [
        'unrevoke',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        atEnrollmentResponse.enrollmentId
      ];
      res = await auth_cli.wrappedMain(args);
      logger.info(
          'Un-Revoked enrollment with enrollmentId: ${atEnrollmentResponse.enrollmentId}');
      // Perform authentication with the unrevoked enrollment-id.
      authResponse = await atOnboardingService.authenticate(
          enrollmentId: atEnrollmentResponse.enrollmentId);
      expect(authResponse, true);
    });

    test('A test to verify password protected of atKeys file', () async {
      // Set pass-phrase to encrypt the atKeys file upon approval of enrollment request.
      (atOnboardingService as AtOnboardingServiceImpl)
          .atOnboardingPreference
          .passPhrase = 'abcd';
      (atOnboardingService as AtOnboardingServiceImpl)
          .atOnboardingPreference
          .hashingAlgoType = HashingAlgoType.argon2id;
      // Submit enrollment request
      AtEnrollmentResponse atEnrollmentResponse = await atOnboardingService
          .sendEnrollRequest(
              'buzz', 'local-device', 'ABC123', {'e2etest': 'rw'});
      logger.info(
          'Submitted enrollment successfully with enrollmentId: ${atEnrollmentResponse.enrollmentId}');
      expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);
      expect(atEnrollmentResponse.enrollmentId.isNotEmpty, true);
      // Approve enrollment request
      List<String> args = [
        'approve',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-i',
        atEnrollmentResponse.enrollmentId
      ];
      var res = await auth_cli.wrappedMain(args);
      expect(res, 0);
      logger.info(
          'Approved enrollment with enrollmentId: ${atEnrollmentResponse.enrollmentId}');

      // Generate Atkeys file for the enrollment request.
      await atOnboardingService.awaitApproval(atEnrollmentResponse);
      await atOnboardingService.createAtKeysFile(atEnrollmentResponse,
          atKeysFile:
              File('storage/keys/@sitaram-apkam-password-protected.atKeys'));

      // Authenticate with APKAM keys
      (atOnboardingService as AtOnboardingServiceImpl)
              .atOnboardingPreference
              .atKeysFilePath =
          'storage/keys/@sitaram-apkam-password-protected.atKeys';
      bool authResponse = await atOnboardingService.authenticate(
          enrollmentId: atEnrollmentResponse.enrollmentId);
      expect(authResponse, true);

      // Run list to ensure the pass-phase is indeed working as expected
      args = [
        'list',
        '-a',
        atSign,
        '-r',
        'vip.ve.atsign.zone',
        '-P',
        (atOnboardingService as AtOnboardingServiceImpl)
            .atOnboardingPreference
            .passPhrase!,
        '-k',
        'storage/keys/@sitaram-apkam-password-protected.atKeys'
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
