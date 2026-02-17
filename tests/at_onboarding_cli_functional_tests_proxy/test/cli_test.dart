import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:at_utils/at_logger.dart';
import '../check_docker_readiness.dart';
import 'package:at_demo_data/at_demo_data.dart';
import '../lib/features/onboard_command.dart';
import '../lib/features/otp_command.dart';
import '../lib/features/enroll_command.dart';
import '../lib/features/list_enrollments_command.dart';
import '../lib/features/approve_command.dart';
import '../lib/features/validate_keys.dart';
import '../lib/features/cleanup_utils.dart';
import '../lib/docker_utils.dart';

const String rootServer = 'proxy:vip.ve.atsign.zone:443';
const String appName = 'noports';
const String namespaces = 'sshnp:rw,sshrvd:rw';

final Uuid _uuid = Uuid();
final logger = AtSignLogger('AtOnboardingFunctionalTestsProxy');

void main() {
  group('Enrollment Workflow Tests', () {
    late String atSign;
    late String masterKeyFile;
    late String deviceName;
    late String enrollmentKeyFile;
    late String generatedOtp;
    late List<String> filesToCleanup;

    setUpAll(() async {
      const int atSignIndex = 31;
      atSign = allAtsigns[atSignIndex];
      masterKeyFile = '${atSign}_master_${_uuid.v4()}_key.atKeys';
      deviceName = _uuid.v4();
      enrollmentKeyFile = '${atSign}_enrolled_${deviceName}_key.atKeys';
      filesToCleanup = [];

      try {
        logger.info('Stopping existing docker compose services (if any)');
        await runDockerComposeDown().timeout(Duration(seconds: 10));
      } catch (e) {
        logger.warning('Exception while stopping existing, will ignore: $e');
      }

      try {
        logger.info('Removing at_proxyserver and at_virtualenv containers');
        await removeDockerContainers(['at_proxyserver', 'at_virtualenv'])
            .timeout(Duration(seconds: 10));
      } catch (e) {
        logger.warning('Exception while removing containers, will ignore: $e');
      }

      logger.info('Starting fresh Docker Compose services...');
      bool restartSuccess = await restartDockerCompose();
      expect(restartSuccess, isTrue,
          reason: 'Docker Compose restart should succeed');

      logger.info('Checking system readiness...');
      bool isReady = await checkDockerContainers();
      expect(isReady, isTrue,
          reason: 'System should be ready with fresh Docker Compose');

      logger.info('Setup: Using atSign: $atSign for enrollment workflow');
    });

    tearDownAll(() async {
      await cleanupTestFiles(filesToCleanup);

      await stopDockerServices();
    });

    test('step 1: fresh onboard to generate master keys', () async {
      await cleanupAllKeyFiles();

      String cramKey = cramKeyMap[atSign] ?? '';

      bool success =
          await onboardAtSign(atSign, cramKey, masterKeyFile, rootServer);
      expect(success, isTrue,
          reason: 'Onboarding should succeed and generate master key file');

      filesToCleanup.add('../../packages/at_onboarding_cli/$masterKeyFile');
    }, timeout: Timeout(Duration(minutes: 3)));

    test('step 2: generate OTP using master keys', () async {
      generatedOtp =
          await generateOtpWithExistingKeys(atSign, masterKeyFile, rootServer);
      expect(generatedOtp.isNotEmpty, isTrue,
          reason: 'OTP should be generated successfully');
      logger.info('Generated OTP: $generatedOtp');
    });

    test('step 3 & 4: submit enrollment request and approve concurrently',
        () async {
      filesToCleanup.add('../../packages/at_onboarding_cli/$enrollmentKeyFile');

      // Start enrollment request (this will wait for approval)
      Future<bool> enrollmentFuture = submitEnrollmentRequest(
          generatedOtp,
          atSign,
          deviceName,
          enrollmentKeyFile,
          rootServer,
          appName,
          namespaces);

      // Give enrollment request a moment to be submitted and start waiting
      await Future.delayed(Duration(seconds: 5));

      // Find and approve the enrollment while Step 3 is waiting
      List<String> enrollmentIds = await listPendingEnrollments(
          atSign, rootServer,
          keyFile: masterKeyFile);
      expect(enrollmentIds.isNotEmpty, isTrue,
          reason: 'Should find pending enrollment requests');

      String enrollmentId = enrollmentIds.first;
      bool approvalSuccess = await approveEnrollment(
          atSign, enrollmentId, masterKeyFile, rootServer);
      expect(approvalSuccess, isTrue,
          reason: 'Enrollment should be approved successfully');

      // Wait for enrollment to complete (should finish after approval)
      bool enrollmentSuccess = await enrollmentFuture;
      expect(enrollmentSuccess, isTrue,
          reason:
              'Enrollment request should complete successfully after approval');
    }, timeout: Timeout(Duration(minutes: 5)));

    test('step 5: validate enrollment keys with list command', () async {
      bool success =
          await validateEnrollmentKeys(atSign, enrollmentKeyFile, rootServer);
      expect(success, isTrue,
          reason: 'Enrollment keys should be valid and functional for listing');
    });
  });
}
