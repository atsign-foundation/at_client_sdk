import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

import 'at_client_cache.dart';
import 'test_keys_dir.dart';
import 'virtualenv_ports.dart';

/// The approving side of an enrollment, driven from a keyfile that holds
/// `__manage`: a passcode for a request to quote, and the decision on it.
///
/// ⚠️ **Every method here opens its own client at `$storageDir/hive/<atSign>/1`,
/// and must evict the cache first.** These run inside tests that have already
/// built a client for the same atSign somewhere else, and
/// `AtClientImpl.atClientInstanceMap` is static and keyed only by
/// `(atSign, enrollmentId)` — so without [evictCachedAtClients] the open
/// below is refused for a client that is already live. The
/// `AtClientManager.getInstance().reset()` each method ends with does not
/// cover that: it runs afterwards, and it leaves the static map populated.
class EnrollmentOperations {
  late String atsign;
  String storageDir = 'test/storage/temp';

  EnrollmentOperations(this.atsign);

  /// A client on [atKeysFilePath], online, through the adapter a program
  /// built on this package uses.
  Future<AtClient> _clientFor(String atKeysFilePath) async {
    await evictCachedAtClients();
    final service = AtOnboardingServiceImpl(
        atsign, getOnboardingPreference(atKeysFilePath: atKeysFilePath));
    if (!await service.authenticate()) {
      throw StateError('$atsign did not come online from $atKeysFilePath: '
          '${service.atClient?.connection.current}');
    }
    return service.atClient!;
  }

  Future<void> _release(AtClient client) async {
    await client.stop();
    AtClientManager.getInstance().reset();
  }

  Future<String?> getOtp(String atKeysFilePath) async {
    final client = await _clientFor(atKeysFilePath);
    final passcode = await client.enrollments.otp();
    stdout.writeln('[Test | EnrollmentOps] Fetched OTP ${passcode.value}');
    await _release(client);
    return passcode.value;
  }

  /// Approves [enrollmentId], or with none the first pending request for
  /// [appName] on [deviceName], and hands back the id approved.
  Future<String> approve(
      {required String atKeysFilePath,
      String? enrollmentId,
      String? appName,
      String? deviceName}) async {
    final client = await _clientFor(atKeysFilePath);
    enrollmentId ??= await _pendingFor(client, appName!, deviceName!);
    await client.enrollments.approve(enrollmentId);
    print('Enroll approved: $enrollmentId');
    await _release(client);
    return enrollmentId;
  }

  /// Denies [enrollmentId], or with none the first pending request for
  /// [appName] on [deviceName], and hands back the id denied.
  Future<String> deny(
      {required String atKeysFilePath,
      String? enrollmentId,
      String? appName,
      String? deviceName}) async {
    final client = await _clientFor(atKeysFilePath);
    enrollmentId ??= await _pendingFor(client, appName!, deviceName!);
    await client.enrollments.deny(enrollmentId);
    print('Enroll denied: $enrollmentId');
    await _release(client);
    return enrollmentId;
  }

  /// The first pending request for [appName] on [deviceName]; the assumption
  /// is that it is the one the test just submitted.
  Future<String> _pendingFor(
      AtClient client, String appName, String deviceName) async {
    final pending = await client.enrollments.list(
        statuses: [EnrollmentStatus.pending], app: appName, device: deviceName);
    if (pending.isEmpty) {
      throw Exception('No pending enrollment requests found for appName: '
          '$appName, deviceName: $deviceName');
    }
    return pending.first.enrollmentId!;
  }

  AtOnboardingPreference getOnboardingPreference(
      {String? cramKey, String? atKeysFilePath}) {
    return AtOnboardingPreference()
      ..commitLogPath = '$storageDir/commitLog/$atsign/1'
      ..hiveStoragePath = '$storageDir/hive/$atsign/1'
      ..rootDomain = 'vip.ve.atsign.zone'
      ..rootPort = virtualenvRootPort
      ..cramSecret = cramKey
      // NOTE: a null here falls through to the home directory's real keys dir.
      ..atKeysFilePath = atKeysFilePath ?? testKeysFile(atsign);
  }
}
