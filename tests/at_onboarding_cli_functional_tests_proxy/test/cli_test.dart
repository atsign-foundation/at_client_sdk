import 'dart:io';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import '../check_docker_readiness.dart';
import 'package:at_demo_data/at_demo_data.dart';
import '../lib/features/onboard_command.dart';
import '../lib/features/otp_command.dart';
import '../lib/features/enroll_command.dart';
import '../lib/features/list_enrollments_command.dart';
import '../lib/features/approve_command.dart';
import '../lib/features/validate_keys.dart';
import '../lib/features/cleanup_utils.dart';
import '../lib/features/docker_utils.dart';

const String rootServer = 'proxy:vip.ve.atsign.zone:443';
const String appName = 'noports';
const String namespaces = 'sshnp:rw,sshrvd:rw';

final Uuid _uuid = Uuid();

void main() {
  group('System Readiness', () {
    test('fresh docker environment setup', () async {
      print('Ensuring clean docker state...');
      try {
        await runDockerComposeDown();
        await removeDockerContainers(['at_proxyserver', 'at_virtualenv']);
      } catch (e) {
        print('Note: Error during cleanup (expected if no containers running): $e');
      }

      print('Starting fresh Docker Compose services...');
      bool restartSuccess = await restartDockerCompose();
      expect(restartSuccess, isTrue, reason: 'Docker Compose restart should succeed');

      print('Checking system readiness...');
      bool isReady = await checkDockerContainers();
      expect(isReady, isTrue, reason: 'System should be ready with fresh Docker Compose');
    });
  });

  group('Enrollment Workflow Tests', () {
    late String atSign;
    late String masterKeyFile;
    late String deviceId;
    late String enrollmentKeyFile;
    late String generatedOtp;
    late List<String> filesToCleanup;

    setUpAll(() {
      const int atSignIndex = 31;
      atSign = allAtsigns[atSignIndex];
      masterKeyFile = '${atSign.substring(1)}_master_${_uuid.v4()}.atKeys';
      deviceId = _uuid.v4();
      enrollmentKeyFile = '${deviceId}_key.atKeys';
      filesToCleanup = [];

      print('Setup: Using atSign: $atSign for enrollment workflow');
    });

    tearDownAll(() async {
      await cleanupTestFiles(filesToCleanup);

      await stopDockerServices();
    });

    test('step 1: fresh onboard to generate master keys', () async {
      await cleanupAllKeyFiles();

      String cramKey = cramKeyMap[atSign] ?? '';

      bool success = await onboardAtSign(atSign, cramKey, masterKeyFile, rootServer);
      expect(success, isTrue, reason: 'Onboarding should succeed and generate master key file');

      filesToCleanup.add('../../packages/at_onboarding_cli/$masterKeyFile');
    }, timeout: Timeout(Duration(minutes: 3)));

    test('step 2: generate OTP using master keys', () async {
      generatedOtp = await generateOtpWithExistingKeys(atSign, masterKeyFile, rootServer);
      expect(generatedOtp.isNotEmpty, isTrue, reason: 'OTP should be generated successfully');
      print('Generated OTP: $generatedOtp');
    });

    test('step 3: submit enrollment request', () async {
      bool success = await submitEnrollmentRequest(generatedOtp, atSign, deviceId, enrollmentKeyFile, rootServer, appName, namespaces);
      expect(success, isTrue, reason: 'Enrollment request should be submitted successfully');

      filesToCleanup.add('../../packages/at_onboarding_cli/$enrollmentKeyFile');
    }, timeout: Timeout(Duration(minutes: 3)));

    test('step 4: list and approve enrollment', () async {
      List<String> enrollmentIds = await listPendingEnrollments(atSign, rootServer, keyFile: masterKeyFile);
      expect(enrollmentIds.isNotEmpty, isTrue, reason: 'Should find pending enrollment requests');

      String enrollmentId = enrollmentIds.first;
      bool success = await approveEnrollment(atSign, enrollmentId, masterKeyFile, rootServer);
      expect(success, isTrue, reason: 'Enrollment should be approved successfully');
    });

    test('step 5: validate enrollment keys', () async {
      bool success = await validateEnrollmentKeys(atSign, enrollmentKeyFile, rootServer);
      expect(success, isTrue, reason: 'Enrollment keys should be valid and functional');
    });
  });

  group('End-to-End Integration', () {
    test('complete enrollment workflow', () async {
      const int atSignIndexE2E = 32;
      String atSign = allAtsigns[atSignIndexE2E];
      String masterKeyFile = '${atSign.substring(1)}_integration_master_${_uuid.v4()}.atKeys';
      String deviceId = _uuid.v4();
      String enrollmentKeyFile = '${deviceId}_key.atKeys';
      List<String> filesToCleanup = [
        '../../packages/at_onboarding_cli/$enrollmentKeyFile',
        '../../packages/at_onboarding_cli/$masterKeyFile'
      ];

      try {
        print('Step 1: Cleaning and fresh onboarding...');
        await cleanupAllKeyFiles();

        String cramKey = cramKeyMap[atSign] ?? '';
        bool onboardSuccess = await onboardAtSign(atSign, cramKey, masterKeyFile, rootServer);
        expect(onboardSuccess, isTrue, reason: 'Onboarding should succeed');

        print('Step 2: Generating OTP...');
        String otp = await generateOtpWithExistingKeys(atSign, masterKeyFile, rootServer);
        expect(otp.isNotEmpty, isTrue);

        print('Step 3: Submitting enrollment request...');
        bool enrollmentSuccess = await submitEnrollmentRequest(otp, atSign, deviceId, enrollmentKeyFile, rootServer, appName, namespaces);
        expect(enrollmentSuccess, isTrue);

        print('Step 4: Listing and approving enrollment...');
        List<String> enrollmentIds = await listPendingEnrollments(atSign, rootServer, keyFile: masterKeyFile);
        expect(enrollmentIds.isNotEmpty, isTrue);

        String enrollmentId = enrollmentIds.first;
        bool approvalSuccess = await approveEnrollment(atSign, enrollmentId, masterKeyFile, rootServer);
        expect(approvalSuccess, isTrue);

        print('Step 5: Validating enrollment keys...');
        bool validationSuccess = await validateEnrollmentKeys(atSign, enrollmentKeyFile, rootServer);
        expect(validationSuccess, isTrue);

        print('✓ Complete enrollment workflow completed successfully');
      } finally {
        await cleanupTestFiles(filesToCleanup);
        await stopDockerServices();
      }
    }, timeout: Timeout(Duration(minutes: 5)));
  });
}