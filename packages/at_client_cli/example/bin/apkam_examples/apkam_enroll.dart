import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';

import '../util/custom_arg_parser.dart';

/// Enrols this device as the `buzz` app, quoting a one-time passcode an
/// already enrolled client issued, and waits for that client to approve.
///
/// The keyfile named is the resume record: run again for the same app and
/// device, the wait picks up where it left off rather than asking again.
Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'finer';
  final argResults = CustomArgParser(getArgParser()).parse(args);

  final String atSign = argResults['atsign'];
  final preference = AtClientPreference()
    ..namespace = 'buzz'
    ..rootDomain = 'vip.ve.atsign.zone';
  final keys = CliKeys.fileFor(atSign, path: argResults['atKeysPath']);
  final lookUps = lookUpsFor(preference.rootDomain);
  final secondaryAddressFinder = CacheableSecondaryAddressFinder(
      preference.rootDomain, preference.rootPort);

  // run otp:get from an enrolled client and pass the passcode
  final pending = await Atsign(atSign).resumeEnrollment(
          app: 'buzz',
          device: 'iphone',
          keys: keys,
          preference: preference,
          lookUps: lookUps,
          secondaryAddressFinder: secondaryAddressFinder) ??
      await Atsign(atSign).enroll(
          otp: argResults['otp'],
          app: 'buzz',
          device: 'iphone',
          namespaces: {'buzz': 'rw'},
          keys: keys,
          preference: preference,
          lookUps: lookUps,
          secondaryAddressFinder: secondaryAddressFinder);
  print('enrollment ${pending.enrollmentId} awaits approval');
  pending.progress.listen((event) => print('${event.group}: ${event.msg}'));

  final client = await pending.client(preference,
      storage: CliKeys.storageFor(atSign,
          program: 'buzz', id: pending.enrollmentId),
      retryInterval: Duration(seconds: 10));
  print('approved: this device runs as enrollment ${client.enrollmentId}');
  await client.stop();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('otp', abbr: 'o', help: 'OTP fetched from your atsign/atServer')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
