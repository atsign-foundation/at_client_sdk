import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';

import '../util/custom_arg_parser.dart';

/// Listens for enrollment requests on an atSign and approves or denies each
/// one from the terminal.
///
/// `dart enroll_app_listen.dart -a <atsign> -k <path_to_key_file>`
void main(List<String> args) async {
  final argResults = CustomArgParser(getArgParser()).parse(args);
  final String atSign = argResults['atsign'];

  final keys = CliKeys.fileFor(atSign, path: argResults['atKeysPath']);
  final enrollmentId = (await keys.read(atSign)).enrollmentToAuthenticateAs();
  final preference = AtClientPreference()..rootDomain = 'vip.ve.atsign.zone';
  final client = await Atsign(atSign).open(
      keys: keys,
      preference: preference,
      namespace: 'wavi',
      storage: CliKeys.storageFor(atSign, program: 'wavi', id: enrollmentId),
      lookUps: lookUpsFor(preference.rootDomain),
      secondaryAddressFinder: CacheableSecondaryAddressFinder(
          preference.rootDomain, preference.rootPort));

  await for (final announced in client.enrollments.requests) {
    final request = await client.enrollments.fetch(announced.enrollmentId!);
    if (request == null) {
      print('enrollment ${announced.enrollmentId} not found');
      continue;
    }
    final Duration? expiry = request.apkamKeysExpiryDuration;
    final String asked = expiry == null
        ? 'an expiry the atServer did not report'
        : expiry <= Duration.zero
            ? 'no expiry'
            : 'keys that expire after $expiry';
    print('Approve enrollment ${request.enrollmentId} from '
        '${request.appName} on ${request.deviceName} for '
        '${request.namespace}, asking for $asked? (yes/no)');
    if (stdin.readLineSync() == 'yes') {
      await client.enrollments.approve(request.enrollmentId!);
      print('approved ${request.enrollmentId}');
    } else {
      await client.enrollments.deny(request.enrollmentId!);
      print('denied ${request.enrollmentId}');
    }
  }
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
