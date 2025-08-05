import 'package:args/args.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

import '../util/custom_arg_parser.dart';

Future<void> main(args) async {
  final argResults = CustomArgParser(getArgParser()).parse(args);

  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'example' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath = argResults['atKeysPath']
    // defaults to '/home/user/.atsign/keys/@atsign_key.atKeys'
    // if your atKeys file is not present at that location, specify the location of the file
    ..rootDomain = 'vip.ve.atsign.zone'
    // users can choose to specify the hiveStoragePath
    //if not specified defaults to /home/user/.atsign/at_onboarding_cli/storage/@atsign/hive
    ..hiveStoragePath = 'home/user/atsign/${argResults['atsign']}/storage/hive'
    // users can choose to specify the commitLogPath
    //if not specified defaults to /home/user/.atsign/at_onboarding_cli/storage/@atsign/commitLog
    ..commitLogPath =
        'home/user/atsign/${argResults['atsign']}/storage/commitLog';

  AtOnboardingService? onboardingService =
      AtOnboardingServiceImpl(argResults['atsign'], atOnboardingPreference);
  await onboardingService.authenticate(); // when authenticating
  AtClient? client = onboardingService.atClient;
  print(await client?.getKeys());
  // print(await atLookup?.scan(regex: 'publickey'));
  await onboardingService.close();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
