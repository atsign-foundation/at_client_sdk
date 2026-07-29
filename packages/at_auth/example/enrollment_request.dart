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
/// Usage: `dart enrollment_request.dart -a <atsign> -o <otp> -r <root_server_domain>`
void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption('otp',
          abbr: 'o', help: 'OTP required for enrollment', mandatory: true)
      ..addOption('rootDomain',
          abbr: 'r',
          help: 'root server domain',
          mandatory: false,
          defaultsTo: 'root.atsign.org');
    final argResults = parser.parse(args);
    AtLookUp atLookUp =
        AtLookupImpl(argResults['atsign'], argResults['rootDomain'], 64);

    AtEnrollment atEnrollmentBase = AtEnrollment.create();

    // The requesting app's session: its atSign, where to reach its atServer,
    // and the atKeysIo destination the newly enrolled keys are persisted into.
    final session = AtAuthSession(
      atsign: argResults['atsign'],
      rootDomain: AtRootDomain(argResults['rootDomain'], 64),
      atKeysIo: FileAtKeysIo(),
    );

    // New app sending enrollment request to server:
    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        session: session,
        appName: 'buzz',
        deviceName: 'pixel',
        namespaces: {'buzz': 'rw'},
        otp: argResults['otp']);

    // submit yields a PendingEnrollment: the server's verdict plus the APKAM
    // keys minted locally, which waitForApproval needs to finish the handshake.
    final pending = await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
    print(pending);

    // Once the approving app approves, waitForApproval completes those keys with
    // the material held by the atServer, persists them into session.atKeysIo,
    // and replaces pending.session with an authenticated one — hand that
    // straight to AtClientManager.fromAuthSession(...).
    // await atEnrollmentBase.waitForApproval(pending);
    // print(pending.session.enrollmentId);
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}
