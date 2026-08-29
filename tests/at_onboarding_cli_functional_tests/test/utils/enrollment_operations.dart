import 'dart:io';

import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';

import 'package:at_client/src/service/enrollment_service_impl.dart';

import 'at_client_cache.dart';
import 'test_keys_dir.dart';

/// Contains methods that perform common enrollment operations like getOtp, approve, etc.
///
/// Each method requires an atKeysFile that has authorization to perform operations
///
/// ⚠️ **Every method here builds its own client at `$storageDir/hive/<atSign>/1`,
/// and must evict the cache first.** These run inside tests that have already
/// built a client for the same atSign somewhere else, and
/// `AtClientImpl.atClientInstanceMap` is static and keyed only by
/// `(atSign, enrollmentId)` — so without [evictCachedAtClients] the service
/// below silently reuses the caller's client and its storage path, and every
/// operation runs against a store this class did not choose.
///
/// The `AtClientManager.getInstance().reset()` at the end of each method does
/// not cover this: it runs after the damage, and it does not clear the static
/// map. See [evictCachedAtClients] for why.
class EnrollmentOperations {
  late String atsign;
  String storageDir = 'test/storage/temp';

  EnrollmentOperations(this.atsign);

  Future<String?> getOtp(String atKeysFilePath) async {
    evictCachedAtClients();
    AtOnboardingService? onboardingService = AtOnboardingServiceImpl(
        atsign, getOnboardingPreference(atKeysFilePath: atKeysFilePath));
    await onboardingService.authenticate();
    String? response = await onboardingService.atClient
        ?.getRemoteSecondary()
        ?.executeCommand('otp:get\n', auth: true);
    stdout.writeln('[Test | EnrollmentOps] Fetch OTP response: $response');
    response = response?.replaceFirst(RegExp(r'^data:'), '');
    await onboardingService.close();
    onboardingService = null;
    AtClientManager.getInstance().reset();
    return response;
  }

  Future<AtEnrollmentResponse> approve(
      {required String atKeysFilePath,
      String? enrollmentId,
      String? encApkamSymmetricKey,
      String? appName,
      String? deviceName}) async {
    evictCachedAtClients();
    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
        atsign, getOnboardingPreference(atKeysFilePath: atKeysFilePath));
    await onboardingService.authenticate();
    EnrollmentService enrollmentService = EnrollmentServiceImpl(
        onboardingService.atClient!, AtEnrollment.create());

    // when enrollmentId is not provided. Fetches all enrollment requests for
    // the given appName and deviceName and uses the data of the first request
    //
    // the assumption is that the first request with the given appName and
    // deviceName is the one that needs to be approved
    Enrollment? enrollment;
    if (enrollmentId == null) {
      enrollment = await fetchEnrollment(enrollmentService,
          appName: appName!, deviceName: deviceName!);
      enrollmentId = enrollment.enrollmentId;
      encApkamSymmetricKey = enrollment.encryptedAPKAMSymmetricKey;
    }
    // ⛔ `?? ''`, not `!`. A pq-mode request carries NO wrapped symmetric key —
    // that absence is the signal `EnrollmentServiceImpl.approve` reads to mint
    // one of its own and swap in `approvedWithMintedKey` — so the null
    // assertion threw for every request built under the default posture once
    // that default became pqReady. Empty lets the decision reach approve(),
    // which is the code that does the right thing.
    EnrollmentRequestDecision decision = EnrollmentRequestDecision.approved(
      enrollmentId: enrollmentId!,
      atSign: atsign,
      apkamSymmetricKey: AtBytes.fromString(encApkamSymmetricKey ?? ''),
    );
    AtEnrollmentResponse? enrollmentResponse =
        await enrollmentService.approve(decision);
    print('Enroll Approve Response: $enrollmentResponse');
    await onboardingService.close();
    AtClientManager.getInstance().reset();
    return enrollmentResponse;
  }

  Future<AtEnrollmentResponse> deny(
      {required String atKeysFilePath,
      String? enrollmentId,
      String? appName,
      String? deviceName}) async {
    evictCachedAtClients();
    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
        atsign, getOnboardingPreference(atKeysFilePath: atKeysFilePath));
    await onboardingService.authenticate();
    EnrollmentService enrollmentService = EnrollmentServiceImpl(
        onboardingService.atClient!, AtEnrollment.create());

    // when enrollmentId is not provided. Fetches all enrollment requests for
    // the given appName and deviceName and uses the data of the first request
    //
    // the assumption is that the first request with the given appName and
    // deviceName is the one that needs to be denied
    Enrollment? enrollment;
    if (enrollmentId == null) {
      enrollment = await fetchEnrollment(enrollmentService,
          appName: appName!, deviceName: deviceName!);
      enrollmentId = enrollment.enrollmentId;
    }
    EnrollmentRequestDecision decision =
        EnrollmentRequestDecision.denied(enrollmentId!, atsign);
    AtEnrollmentResponse? enrollmentResponse =
        await enrollmentService.deny(decision);
    print('Enroll Approve Response: $enrollmentResponse');
    await onboardingService.close();
    AtClientManager.getInstance().reset();
    return enrollmentResponse;
  }

  /// Fetches enrollment requests from server based on the [appName] and [deviceName] provided
  ///
  /// Always returns the first enrollment from the list fetched from server
  Future<Enrollment> fetchEnrollment(EnrollmentService enrollmentService,
      {required String appName, required String deviceName}) async {
    EnrollmentListRequestParam requestParam = EnrollmentListRequestParam()
      ..appName = appName
      ..deviceName = deviceName
      ..enrollmentListFilter = [EnrollmentStatus.pending];

    List<Enrollment> enrollments = await enrollmentService
        .fetchEnrollmentRequests(enrollmentListParams: requestParam);

    if (enrollments.isEmpty) {
      throw Exception(
          'No pending enrollment requests found for appName: $appName, deviceName: $deviceName');
    }

    return enrollments[0];
  }

  AtOnboardingPreference getOnboardingPreference(
      {String? cramKey, String? atKeysFilePath}) {
    return AtOnboardingPreference()
      ..commitLogPath = '$storageDir/commitLog/$atsign/1'
      ..hiveStoragePath = '$storageDir/hive/$atsign/1'
      ..rootDomain = 'vip.ve.atsign.zone'
      ..cramSecret = cramKey
      // A null here would fall through to the home directory's real keys dir.
      ..atKeysFilePath = atKeysFilePath ?? testKeysFile(atsign);
  }
}
