import 'dart:io';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import '../check_docker_readiness.dart';
import '../lib/at_demo_data_wrapper.dart';
import '../lib/features/onboard_command.dart';
import '../lib/features/otp_command.dart';
import '../lib/features/enroll_command.dart';
import '../lib/features/list_enrollments_command.dart';
import '../lib/features/approve_command.dart';
import '../lib/features/validate_keys.dart';
import '../lib/features/cleanup_utils.dart';

const String rootServer = 'vip.ve.atsign.zone:443';
const String appName = 'noports';
const String namespaces = 'sshnp:rw,sshrvd:rw';

final Uuid _uuid = Uuid();

void main() {
  group('System Readiness', () {
    test('fresh docker environment setup', () async {
      // Ensure completely clean state by stopping any existing containers
      print('Ensuring clean docker state...');
      try {
        await Process.run('docker-compose', ['down']);
        await Process.run('docker', ['rm', '-f', 'at_proxyserver', 'at_virtualenv']);
      } catch (e) {
        print('Note: Error during cleanup (expected if no containers running): $e');
      }

      // Start fresh
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
      atSign = atSignData['atSign']!; // Use @gary for both onboarding and enrollment
      masterKeyFile = 'gary_master_${_uuid.v4()}.atKeys';
      deviceId = _uuid.v4();
      enrollmentKeyFile = '${deviceId}_key.atKeys';
      filesToCleanup = [];

      print('Setup: Using atSign: $atSign for enrollment workflow');
    });

    tearDownAll(() async {
      // Clean up key files
      await cleanupTestFiles(filesToCleanup);

      // Stop docker containers
      await stopDockerServices();
    });

    test('step 1: fresh onboard to generate master keys', () async {
      // Clean up any existing key files first to ensure fresh start
      await cleanupAllKeyFiles();

      // Fresh onboarding
      String cramKey = atSignData['cramKey']!;

      bool success = await onboardAtSign(atSign, cramKey, masterKeyFile, rootServer);
      expect(success, isTrue, reason: 'Onboarding should succeed and generate master key file');

      // Add to cleanup list
      filesToCleanup.add('../../packages/at_onboarding_cli/$masterKeyFile');
    });

    test('step 2: generate OTP using master keys', () async {
      generatedOtp = await generateOtpWithExistingKeys(atSign, masterKeyFile, rootServer);
      expect(generatedOtp.isNotEmpty, isTrue, reason: 'OTP should be generated successfully');
      print('Generated OTP: $generatedOtp');
    });

    test('step 3: submit enrollment request', () async {
      bool success = await submitEnrollmentRequest(generatedOtp, atSign, deviceId, enrollmentKeyFile, rootServer, appName, namespaces);
      expect(success, isTrue, reason: 'Enrollment request should be submitted successfully');

      // Add enrollment key file to cleanup list
      filesToCleanup.add('../../packages/at_onboarding_cli/$enrollmentKeyFile');
    });

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
      String atSign = atSignData['atSign']!;
      String masterKeyFile = 'integration_master_${_uuid.v4()}.atKeys';
      String deviceId = _uuid.v4();
      String enrollmentKeyFile = '${deviceId}_key.atKeys';
      List<String> filesToCleanup = [
        '../../packages/at_onboarding_cli/$enrollmentKeyFile',
        '../../packages/at_onboarding_cli/$masterKeyFile'
      ];

      try {
        // Step 1: Clean up and fresh onboard
        print('Step 1: Cleaning and fresh onboarding...');
        await cleanupAllKeyFiles();

        String cramKey = atSignData['cramKey']!;
        bool onboardSuccess = await onboardAtSign(atSign, cramKey, masterKeyFile, rootServer);
        expect(onboardSuccess, isTrue, reason: 'Onboarding should succeed');

        // Step 2: Generate OTP
        print('Step 2: Generating OTP...');
        String otp = await generateOtpWithExistingKeys(atSign, masterKeyFile, rootServer);
        expect(otp.isNotEmpty, isTrue);

        // Step 3: Submit enrollment request
        print('Step 3: Submitting enrollment request...');
        bool enrollmentSuccess = await submitEnrollmentRequest(otp, atSign, deviceId, enrollmentKeyFile, rootServer, appName, namespaces);
        expect(enrollmentSuccess, isTrue);

        // Step 4: List and approve enrollment
        print('Step 4: Listing and approving enrollment...');
        List<String> enrollmentIds = await listPendingEnrollments(atSign, rootServer, keyFile: masterKeyFile);
        expect(enrollmentIds.isNotEmpty, isTrue);

        String enrollmentId = enrollmentIds.first;
        bool approvalSuccess = await approveEnrollment(atSign, enrollmentId, masterKeyFile, rootServer);
        expect(approvalSuccess, isTrue);

        // Step 5: Validate enrollment keys
        print('Step 5: Validating enrollment keys...');
        bool validationSuccess = await validateEnrollmentKeys(atSign, enrollmentKeyFile, rootServer);
        expect(validationSuccess, isTrue);

        print('✓ Complete enrollment workflow completed successfully');
      } finally {
        await cleanupTestFiles(filesToCleanup);
        await stopDockerServices();
      }
    });
  });
}