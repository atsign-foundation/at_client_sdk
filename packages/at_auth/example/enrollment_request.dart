import 'dart:io';

import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
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

    // New app sending enrollment request to server:
    AtEnrollmentRequest enrollmentRequest = AtEnrollmentRequest(
        atSign: argResults['atsign'],
        appName: 'buzz',
        deviceName: 'pixel',
        namespaces: {'buzz': 'rw'},
        otp: argResults['otp']);

    // Contains the response from the server.
    final atEnrollmentResponse =
        await atEnrollmentBase.submit(enrollmentRequest, atLookUp);
    print(atEnrollmentResponse);
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}
