/// The default 30-second budget is far too small here: these long-lived CI
/// atSigns carry commit logs of hundreds of thousands of entries, and a fresh
/// runner replays from commit id -1 while the enrollment verbs share the same
/// connection. Fifteen minutes is chosen to be uninteresting rather than
/// tight; a run that genuinely hangs still fails, just later.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/sync_service_impl.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/enrollment_approval.dart';
import 'package:at_end2end_test/src/run_marker.dart';
import 'package:at_end2end_test/src/setup_outcome.dart';
import 'package:at_end2end_test/src/test_initializers.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// Intentionally did not prefix/suffix the file name with test to refrain from running this in the test suite.

/// Stops the current client's sync, which this script never needs: enrollments
/// are submitted and approved over the remote secondary, and replaying the
/// commit logs these atSigns carry is pure cost.
///
/// ⚠️ Only the periodic timer and any later run stop — a sync already in flight
/// runs to completion, and switching to another atSign builds a fresh sync
/// service that starts immediately.
Future<void> _stopSync() async {
  final syncService = AtClientManager.getInstance().atClient.syncService;
  if (syncService is SyncServiceImpl) {
    await syncService.stop();
  }
}

/// How long each enrollment's APKAM keys last. The atServer retires the
/// enrollment when they expire, and nothing in this pack denies or revokes
/// one.
const Duration _keyExpiry = Duration(hours: 3);

/// How far the atServer's clock may run ahead of this runner's before the
/// expiry check refuses.
const Duration _clockAllowance = Duration(minutes: 10);

void main() {
  List atSignList = ConfigUtil.getYaml()['enrollment']['atsignList'];
  String namespace = TestConstants.namespace;
  final marker = runMarker(Platform.environment);
  // NOTE: tearDownAll ends the process before the runner reports, so the exit
  // code it derives from this set is what the CI step reads.
  final completed = <String>{};

  setUpAll(() async {
    for (var atSign in atSignList) {
      await TestSuiteInitializer.getInstance().testInitializer(
          atSign, namespace, 'pkam',
          enableInitialSync: false, posture: PqPosture.legacy);
      await _stopSync();
    }
  });

  group(
      'Every enrollment the setup approves is one the atServer retires by itself',
      () {
    for (var currentAtSign in atSignList) {
      test('A test to submit and approve an enrollment for $currentAtSign',
          () async {
        // Set SPP at the start of enrollment tests to pass as OTP.
        await TestSuiteInitializer.getInstance().testInitializer(
            currentAtSign, namespace, 'pkam',
            enableInitialSync: false, posture: PqPosture.legacy);
        await _stopSync();
        // Set SPP into the Remote Secondary
        var atClient = AtClientManager.getInstance().atClient;
        var otp = (await atClient.getOTP()).response;
        final rootDomain = AtRootDomain(atClient.getPreferences()!.rootDomain,
            atClient.getPreferences()!.rootPort);

        // The session names the keyfile the suite's clients open on, so the
        // approval completes the keys straight into it. FileAtKeysIo.write
        // refuses to overwrite, so a keyfile a previous run left is removed.
        final keyfile = File(
            "${ConfigUtil.getYaml()['filePath']}/${currentAtSign}_key.atKeys");
        if (keyfile.existsSync()) keyfile.deleteSync();
        keyfile.parent.createSync(recursive: true);
        final session = AtAuthSession(
            atSign: currentAtSign,
            rootDomain: rootDomain,
            atKeysIo: FileAtKeysIo(filePath: (_) => keyfile.path));

        // Submit an enrollment request with at_auth package
        AtEnrollment atEnrollmentBase = AtEnrollment.create();
        int random = Uuid().v4().hashCode;
        AtLookUp atLookUp = secureSocketLookUps()(
            atSign: currentAtSign, rootDomain: rootDomain, authenticator: null);

        // Do an enrollment with access to the __config namespace
        AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
            session: session,
            appName: enrollmentAppName(marker, random),
            deviceName: 'iphone',
            otp: otp,
            namespaces: {TestConstants.namespace: 'rw', '__config': 'rw'},
            signingAlgo: SigningAlgoType.rsa2048,
            apkamKeysExpiryDuration: _keyExpiry);
        final AtEnrollmentResponse atEnrollmentResponse;
        try {
          atEnrollmentResponse =
              await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
        } finally {
          await atLookUp.close();
        }
        expect(atEnrollmentResponse.enrollStatus, EnrollmentStatus.pending);

        // Use enroll fetch to get the encryptedAPKAMSymmetricKey
        String? enrollmentFetchResponse = await atClient
            .getRemoteSecondary()
            ?.executeCommand(
                'enroll:fetch:{"enrollmentId":"${atEnrollmentResponse.enrollmentId}"}\n',
                auth: true);
        enrollmentFetchResponse =
            enrollmentFetchResponse?.replaceAll('data:', '');
        Enrollment enrollment =
            Enrollment.fromJSON(jsonDecode(enrollmentFetchResponse!));

        // Approve enrollment
        AtEnrollmentResponse? approveEnrollmentResponse =
            await atClient.enrollmentService?.approve(
          EnrollmentRequestDecision.approved(
              enrollmentId: atEnrollmentResponse.enrollmentId,
              apkamSymmetricKey:
                  AtBytes.fromString(enrollment.encryptedAPKAMSymmetricKey!),
              atSign: currentAtSign),
        );
        expect(
            approveEnrollmentResponse?.enrollStatus, EnrollmentStatus.approved);
        final approvedBy = DateTime.now().toUtc();

        final enrollmentId = atEnrollmentResponse.enrollmentId;
        final approved = jsonDecode((await atClient
                .getRemoteSecondary()
                ?.executeCommand(
                    'enroll:fetch:{"enrollmentId":"$enrollmentId"}\n',
                    auth: true))!
            .replaceAll('data:', '')) as Map<String, dynamic>;
        expect(approved['appName'], enrollmentRequest.appName,
            reason: 'the atServer holds enrollment $enrollmentId on '
                '$currentAtSign under a different appName from the one '
                'submitted, so its roster no longer names the run that made it');
        final expiresAt = DateTime.tryParse('${approved['expiresAt']}');
        expect(expiresAt, isNotNull,
            reason: 'enrollment $enrollmentId on $currentAtSign has no expiry '
                '(expiresAt: ${approved['expiresAt']}), so the atServer keeps it '
                'for good and nothing else retires it');
        // NOTE: the atServer's clock against this runner's, hence the allowance.
        expect(expiresAt!.isAfter(approvedBy.add(_keyExpiry + _clockAllowance)),
            isFalse,
            reason: 'enrollment $enrollmentId on $currentAtSign expires at '
                '$expiresAt, more than $_keyExpiry after its approval at '
                '$approvedBy, so the atServer keeps it longer than this pack '
                'relies on');

        // Awaiting the approval collects the two atSign-wide secrets it
        // released and writes the completed keys into the keyfile.
        await awaitEnrollmentApproval(atEnrollmentResponse,
            atSign: currentAtSign, rootDomain: rootDomain);

        // Set AtClient to null and authenticate with the new auth keys generated for enrollment
        AtClientManager.getInstance().removeAllChangeListeners();
        AtClientImpl.atClientInstanceMap.clear();

        // The keyfile authenticates as the enrollment, which is what the
        // suite's clients open on.
        expect(
            await Atsign(currentAtSign).authenticatesAs(
                keys: session.atKeysIo, rootDomain: rootDomain),
            atEnrollmentResponse.enrollmentId);
        print(
            'Completed enrollment setup of the atSign: $currentAtSign with enrollment Id: ${atEnrollmentResponse.enrollmentId} with access to ${enrollmentRequest.namespaces}');
        completed.add(currentAtSign);
      });
    }
  });

  tearDownAll(() async {
    AtClientManager.getInstance().removeAllChangeListeners();
    AtClientManager.getInstance()
        .atClient
        .notificationService
        .stopAllSubscriptions();
    exit(setupExitCode(atSignList.cast<String>(), completed));
  });
}
