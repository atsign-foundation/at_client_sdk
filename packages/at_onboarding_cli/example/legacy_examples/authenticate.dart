import 'package:args/args.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';

import '../util/custom_arg_parser.dart';

/// The adapter a program written against earlier versions of this package
/// keeps: `authenticate()` opens the client from the keyfile and makes it the
/// manager's current client. A new program calls `Atsign.open` directly, as
/// `apkam_examples/apkam_authenticate.dart` does.
Future<void> main(List<String> args) async {
  final argResults = CustomArgParser(getArgParser()).parse(args);

  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'example' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath = argResults['atKeysPath']
    // defaults to '/home/user/.atsign/keys/@atsign_key.atKeys'
    // if your atKeys file is not present at that location, specify the location of the file
    ..rootDomain = 'vip.ve.atsign.zone'
    // users can choose to specify the storagePath
    // if not specified defaults to /home/user/.atsign/at_onboarding_cli/storage/@atsign/hive
    ..storagePath = 'home/user/atsign/${argResults['atsign']}/storage/hive';

  AtOnboardingService onboardingService =
      AtOnboardingServiceImpl(argResults['atsign'], atOnboardingPreference);
  final online = await onboardingService.authenticate();
  AtClient? client = onboardingService.atClient;
  print('online: $online; connection: ${client?.connection.current}');
  print(await client?.getKeys());
  await client?.stop();
}

ArgParser getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}
