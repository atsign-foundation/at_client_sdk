import 'dart:io';
import 'package:args/args.dart';
import 'package:at_auth/at_auth_io.dart';

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

    // secureSocketProbe (from at_auth_io.dart) polls the atServer until it is
    // listening — a freshly-registered atSign can take minutes to provision.
    final atAuth = AtAuth.create(probeSocket: secureSocketProbe);
    final atSign = argResults['atsign'];
    // onboard() generates the keypairs, so it needs somewhere to persist them.
    // There is no default — say where explicitly.
    final atOnboardingRequest = AtOnboardingRequest(atSign)
      ..rootDomain = argResults['rootDomain']
      ..atKeysIo = FileAtKeysIo(filePath: (_) => argResults['keysFilePath']);
    final atOnboardingResponse =
        await atAuth.onboard(atOnboardingRequest, argResults['cramsecret']);
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
