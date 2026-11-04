import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';

import 'util/custom_arg_parser.dart';

/// Activates an atSign with its CRAM secret, writing its first keys to the
/// keyfile named. Without the secret, `at_activate onboard -a <atSign>`
/// fetches one from the registrar against an emailed verification code.
Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'finest';

  final argResults = CustomArgParser(getArgParser()).parse(args);

  final String atSign = argResults['atsign'];
  final preference = AtClientPreference()
    ..namespace = 'wavi'
    ..rootDomain = 'vip.ve.atsign.zone';

  final client = await Atsign(atSign).activate(
      cramSecret: argResults['cram'],
      keys: CliKeys.fileFor(atSign, path: argResults['atKeysPath']),
      preference: preference,
      storage: CliKeys.storageFor(atSign, program: 'wavi'),
      lookUps: lookUpsFor(preference.rootDomain),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort),
      onProgress: (event) => print('${event.group}: ${event.msg}'));
  print('$atSign is activated; its first enrollment is '
      '${client.enrollmentId}, and its keys are at ${argResults['atKeysPath']}');
  await client.stop();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('cram', abbr: 'c', help: 'CRAM secret for the atsign')
    ..addOption('atKeysPath', abbr: 'k', help: 'path to save keys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
