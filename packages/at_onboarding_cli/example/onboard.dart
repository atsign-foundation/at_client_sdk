import 'package:args/args.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

import 'util/custom_arg_parser.dart';

/// Activates an atSign with its CRAM secret, writing its first keys to the
/// keyfile named. Run `get_cram_key.dart` first if you do not hold the secret.
Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'finest';

  final argResults = CustomArgParser(getArgParser()).parse(args);

  final String atSign = argResults['atsign'];
  final preference = AtOnboardingPreference()
    ..namespace =
        'wavi' // unique identifier that can be used to identify data from your app
    ..rootDomain = 'vip.ve.atsign.zone'
    ..storagePath = 'storage/$atSign';

  final client = await Atsign(atSign).activate(
      cramSecret: argResults['cram'],
      keys: FileAtKeysIo(filePath: (_) => argResults['atKeysPath']),
      preference: preference,
      storage: preference.storageFor(atSign),
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
