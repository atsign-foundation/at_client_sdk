import 'dart:io';
import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart' show AtRootDomain;

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

    final enrollmentId = await activateAtSign(
      atSign: argResults['atsign'],
      cramSecret: argResults['cramsecret'],
      keys: FileAtKeysIo(filePath: (_) => argResults['keysFilePath']),
      signingAlgo: SigningAlgoType.rsa2048,
      rootDomain: AtRootDomain(argResults['rootDomain'], 64),
      onProgress: (event) => print('${event.group}: ${event.msg}'),
    );
    print('activated ${argResults['atsign']} as enrollment $enrollmentId; '
        'keys written to ${argResults['keysFilePath']}');
  } on Exception catch (e, trace) {
    print(trace);
  } on ArgumentError catch (e, trace) {
    print(e.message);
    print(trace);
  } finally {
    exit(0);
  }
}
