import 'dart:io';
import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart' show AtRootDomain, AtsignString;

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
    final atsign = (argResults['atsign'] as String).toAtsign();

    // Mints the keys, enrolls them, authenticates, and writes the .atKeys file
    // through the AtKeysIo. Returns nothing: completing without throwing is the
    // success signal.
    await atAuth.onboard(
      atsign,
      AtRootDomain(argResults['rootDomain'], 64),
      FileAtKeysIo(filePath: (_) => argResults['keysFilePath']),
      argResults['cramsecret'],
    );

    // atAuth.atLookUp is the PKAM-authenticated connection onboarding ended on,
    // ready to hand to client creation instead of opening a second one.
    print('onboarded $atsign '
        '(enrollmentId: ${atAuth.atLookUp?.enrollmentId})');
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
