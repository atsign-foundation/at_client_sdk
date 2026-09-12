import 'package:args/args.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

import '../util/custom_arg_parser.dart';

/// Opens a client on an enrolled keyfile. The keyfile names the enrollment
/// the client runs as; nothing has to be read out of it first.
Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'info';
  final argResults = CustomArgParser(getArgParser()).parse(args);

  final String atSign = argResults['atsign'];
  final preference = AtOnboardingPreference()
    ..namespace =
        'wavi' // unique identifier that can be used to identify data from your app
    ..rootDomain = 'vip.ve.atsign.zone'
    ..storagePath = 'storage/$atSign';

  final client = await Atsign(atSign).open(
      keys: FileAtKeysIo(filePath: (_) => argResults['atKeysPath']),
      preference: preference,
      storage: preference.storageFor(atSign));
  print('running as enrollment ${client.enrollmentId}; the connection is '
      '${client.connection.current}');
  print(await client.getKeys());
  await client.stop();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
