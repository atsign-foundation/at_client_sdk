import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';

import '../util/custom_arg_parser.dart';

/// Opens a client on an enrolled keyfile. The keyfile names the enrollment
/// the client runs as, and the client keeps that enrollment's own store.
Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'info';
  final argResults = CustomArgParser(getArgParser()).parse(args);

  final String atSign = argResults['atsign'];
  final preference = AtClientPreference()
    ..namespace = 'wavi'
    ..rootDomain = 'vip.ve.atsign.zone';
  final keys = CliKeys.fileFor(atSign, path: argResults['atKeysPath']);
  final enrollmentId = (await keys.read(atSign)).enrollmentToAuthenticateAs();

  final client = await Atsign(atSign).open(
      keys: keys,
      preference: preference,
      storage: CliKeys.storageFor(atSign, program: 'wavi', id: enrollmentId),
      lookUps: secureSocketLookUps(),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));
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
