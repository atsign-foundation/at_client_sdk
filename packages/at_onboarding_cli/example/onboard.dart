import 'package:args/args.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

import 'util/custom_arg_parser.dart';

Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'finest';

  final argResults = CustomArgParser(getArgParser()).parse(args);

  final atSign = argResults['atsign'];
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'wavi' // unique identifier that can be used to identify data from your app
    ..cramSecret = argResults['cram']
    ..atKeysFilePath = argResults['atKeysPath']
    ..appName = 'wavi'
    ..deviceName = 'pixel'
    ..rootDomain = 'vip.ve.atsign.zone';
  AtOnboardingService? onboardingService =
      AtOnboardingServiceImpl(atSign, atOnboardingPreference);
  await onboardingService.onboard();
  await onboardingService.close();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('cram', abbr: 'c', help: 'CRAM secret for the atsign')
    ..addOption('atKeysPath', abbr: 'k', help: 'path to save keys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
