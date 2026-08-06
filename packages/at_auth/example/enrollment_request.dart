import 'dart:io';

import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// Requests for an enrollment
/// Enrollment request will be submitted to server and marked as pending
/// To get the otp, run otp:get from authenticated privileged client using openssl terminal
/// A privileged at_onboarding_cli client will get the enrollment notification. Check [https://github.com/atsign-foundation/at_libraries/blob/trunk/packages/at_onboarding_cli/example/apkam_examples/enroll_app_listen.dart]
/// Approve or deny the enrollment request from at_onboarding_cli client
/// Usage: `dart enrollment_request.dart -a <atsign> -o <otp> -k <path_to_save_atkeys_file> -r <root_server_domain>`
void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption('otp',
          abbr: 'o', help: 'OTP required for enrollment', mandatory: true)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path to store .atKeys file', mandatory: true)
      ..addOption('rootDomain',
          abbr: 'r',
          help: 'root server domain',
          mandatory: false,
          defaultsTo: 'root.atsign.org');
    final argResults = parser.parse(args);

    final atsign = (argResults['atsign'] as String).toAtsign();
    final rootDomain = AtRootDomain(argResults['rootDomain'], 64);
    // Where the enrolled keys land once the request is approved.
    final atKeysIo = FileAtKeysIo(filePath: (_) => argResults['keysFilePath']);

    // The requesting app has no keys yet, so it submits over a connection built
    // without a PKAM key — the OTP is what authorises the request.
    AtLookUp atLookUp =
        AtLookUp.legacy(atsign, rootDomain.rootDomain, rootDomain.rootPort);

    AtEnrollment atEnrollmentBase = AtEnrollment.create(atLookUp);

    // New app sending enrollment request to server:
    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        atsign: atsign,
        appName: 'buzz',
        deviceName: 'pixel',
        namespaces: [
          NamespacePermission(namespace: 'buzz', read: true, write: true)
        ],
        otp: argResults['otp']);

    // Submitting an AtEnrollmentRequest yields a PendingEnrollment: the
    // server's verdict plus the APKAM keys minted locally, which waitForApproval
    // needs to finish the handshake.
    final pending =
        await atEnrollmentBase.enroll(enrollmentRequest) as PendingEnrollment;
    print('submitted ${pending.enrollmentId} (${pending.enrollStatus.name})');

    // Once the approving app approves, waitForApproval completes those keys with
    // the material held by the atServer and writes them through atKeysIo. It
    // PKAMs on its own connection, built from the APKAM keypair minted above —
    // atLookUp was constructed before that keypair existed. Pass
    // `atLookUpFactory:` to AtEnrollment.create to build that connection
    // yourself.
    await atEnrollmentBase.waitForApproval(
        atsign, rootDomain, atKeysIo, pending);
    print('approved: keys written for $atsign');
  } on Exception catch (e, trace) {
    print(e);
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}
