import 'dart:io';
import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';

/// Perform initial onboarding for an atsign
/// 1. CRAM authentication
/// 2. PKAM authentication with privilege to approve/deny future enrollment requests
/// 3. Generate .atKeys file in the path passed as arg
/// Usage: `dart onboard.dart -a <atsign> -c <cram_secret> -k <path_to_save_atkeys_file> -r <root_server_domain>`
void main(List<String> args) async {
  try {
    final parser = ArgParser()
      ..addOption('atsign',
          abbr: 'a', help: 'atSign to onboard', mandatory: true)
      ..addOption('cramsecret', abbr: 'c', help: 'CRAM secret', mandatory: true)
      ..addOption('keysFilePath',
          abbr: 'k', help: 'Path to store .atKeys file', mandatory: true)
      ..addOption('rootDomain',
          abbr: 'r',
          help: 'root server domain',
          mandatory: false,
          defaultsTo: 'root.atsign.org');
    final argResults = parser.parse(args);

    final atAuth = AtAuth.create();
    final atSign = argResults['atsign'];
    final atOnboardingRequest = AtOnboardingRequest(atSign)
      ..rootDomain = argResults['rootDomain'];
    final atOnboardingResponse =
        await atAuth.onboard(atOnboardingRequest, argResults['cramsecret']);
    if (atOnboardingResponse.isSuccessful) {
      await _generateAtKeysFile(atOnboardingResponse.enrollmentId,
          atOnboardingResponse.atAuthKeys!, atSign, argResults['keysFilePath']);
    }
    print('atOnboardingResponse: $atOnboardingResponse');
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}

Future<void> _generateAtKeysFile(String? enrollmentId, AtKeys atAuthKeys,
    String atSign, String filePath) async {
  var fileAtKeysIo = FileAtKeysIo(filePath: filePath);
  await fileAtKeysIo.write(atSign, atAuthKeys);
}
