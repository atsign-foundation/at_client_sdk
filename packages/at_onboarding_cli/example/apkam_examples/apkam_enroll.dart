import 'package:args/args.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

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
  final preference = AtOnboardingPreference()
    ..namespace =
        'buzz' // unique identifier that can be used to identify data from your app
    ..rootDomain = 'vip.ve.atsign.zone'
    ..storagePath = 'storage/$atSign';
  final keys = FileAtKeysIo(filePath: (_) => argResults['atKeysPath']);

  // run otp:get from an enrolled client and pass the passcode
  final pending = await Atsign(atSign).resumeEnrollment(
          app: 'buzz', device: 'iphone', keys: keys, preference: preference) ??
      await Atsign(atSign).enroll(
          otp: argResults['otp'],
          app: 'buzz',
          device: 'iphone',
          namespaces: {'buzz': 'rw'},
          keys: keys,
          preference: preference);
  print('enrollment ${pending.enrollmentId} awaits approval');
  pending.progress.listen((event) => print('${event.group}: ${event.msg}'));

  final client = await pending.client(preference,
      storage: preference.storageFor(atSign),
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
