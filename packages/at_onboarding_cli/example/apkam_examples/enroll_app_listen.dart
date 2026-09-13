import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client/at_client.dart';

import '../util/atsign_preference.dart';
import '../util/custom_arg_parser.dart';

/// Listens for enrollment requests on an atSign and approves or denies each
/// one from the terminal.
///
/// `dart enroll_app_listen.dart -a <atsign> -k <path_to_key_file>`
void main(List<String> args) async {
  final argResults = CustomArgParser(getArgParser()).parse(args);
  final String atSign = argResults['atsign'];

  final keys = FileAtKeysIo(filePath: (_) => argResults['atKeysPath']);
  final enrollmentId = (await keys.read(atSign)).enrollmentToAuthenticateAs();
  final client = await Atsign(atSign).open(
      keys: keys,
      preference: AtSignPreference.getAlicePreference(atSign, enrollmentId),
      namespace: 'wavi');

  await for (final request in client.enrollments.requests) {
    print('Approve enrollment ${request.enrollmentId} from '
        '${request.appName} on ${request.deviceName} for '
        '${request.namespace}? (yes/no)');
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
