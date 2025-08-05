import 'package:args/args.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

import '../util/custom_arg_parser.dart';

Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'finer';
  final argResults = CustomArgParser(getArgParser()).parse(args);

  final atSign = argResults['atsign'];
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'buzz' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath = argResults['atKeysPath']
    ..appName = 'buzz'
    ..deviceName = 'iphone'
    ..rootDomain = 'vip.ve.atsign.zone';
  AtOnboardingService? onboardingService =
      AtOnboardingServiceImpl(atSign, atOnboardingPreference);
  Map<String, String> namespaces = {"buzz": "rw"};
  // run totp:get from enrolled client and pass the otp
  var enrollmentResponse = await onboardingService.enroll(
    'buzz',
    'iphone',
    argResults['otp'],
    namespaces,
    retryInterval: Duration(seconds: 10),
  );
  print('enrollmentResponse: $enrollmentResponse');
}

getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('otp', abbr: 'o', help: 'OTP fetched from your atsign/atServer')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
