import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_onboarding_cli/src/onboard/at_onboarding_service.dart';
import 'package:at_onboarding_cli/src/onboard/at_onboarding_service_impl.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_preference.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';

import 'home_directory_util.dart';

/// A client for the commands that only read or administer an atSign — `otp`,
/// `list`, `spp`, `approve` and the rest.
///
/// [posture] is how far into the post-quantum rollout this invocation runs;
/// null means whatever the at_client this was built against defaults to. It is
/// optional because this function is exported and apps already call it, but a
/// command that has a `--posture` to pass and does not pass it silently runs
/// at another stage than the one the user named.
Future<AtClient> createAtClient(
    {required String atSign,
    String? atKeysFilePath,
    String? rootDomain,
    String? passPhrase,
    PqPosture? posture}) async {
  final int maxConnectAttempts = 5;
  String nameSpace = 'at_activate';
  atSign = AtUtils.fixAtSign(atSign);
  String? homeDir = HomeDirectoryUtil.homeDir;

  storageDir = HomeDirectoryUtil.standardAtClientStorageDir(
    atSign: atSign,
    progName: nameSpace,
    uniqueID: '${DateTime.now().millisecondsSinceEpoch}',
  );

  // Get file path from the user. If null, search atKeys in the default filePath in user home directory.
  String atKeysFilePathToUse =
      (atKeysFilePath ?? '$homeDir/.atsign/keys/${atSign}_key.atKeys')
          .replaceAll('/', Platform.pathSeparator);
  String? localStoragePathToUse = storageDir?.path;
  String? commitLogStoragePathToUse =
      ('${storageDir?.path}/commit').replaceAll('/', Platform.pathSeparator);
  String downloadPathToUse = ('$homeDir!/.atsign/downloads/$atSign/$nameSpace')
      .replaceAll('/', Platform.pathSeparator);

  String rootServer = rootDomain ?? AuthCliArgs.defaultAtDirectoryFqdn;
  
  // Parse rootServer using AtRootDomain
  AtRootDomain parsedRootDomain = AtRootDomain.parse(rootServer);
  
  AtOnboardingPreference atOnboardingPreference =
      AuthCliArgs.preferenceUnder(posture)
        ..atKeysFilePath = atKeysFilePathToUse
        ..namespace = nameSpace
        ..rootDomain = parsedRootDomain.rootDomain
        ..rootPort = parsedRootDomain.rootPort
        ..passPhrase = passPhrase
        ..hiveStoragePath = localStoragePathToUse
        ..commitLogPath = commitLogStoragePathToUse
        ..downloadPath = downloadPathToUse;

  AtOnboardingService atOnboardingService = AtOnboardingServiceImpl(
      atSign, atOnboardingPreference,
      atServiceFactory: ServiceFactoryWithNoOpSyncService());

  bool authenticated = false;
  Duration retryDuration = Duration(seconds: 3);
  int attempts = 0;
  while (!authenticated && attempts < maxConnectAttempts) {
    try {
      stderr.write(chalk.brightBlue('\r\x1b[KConnecting ... '));
      attempts++;
      await Future.delayed(Duration(
          milliseconds:
              1000)); // Pause just long enough for the retry to be visible
      authenticated = await atOnboardingService.authenticate();
    } catch (exception) {
      stderr.write(chalk.brightRed(
          '$exception. Will retry in ${retryDuration.inSeconds} seconds'));
    }
    if (!authenticated) {
      await Future.delayed(retryDuration);
    }
  }
  if (!authenticated) {
    stderr.writeln();
    var msg = 'Failed to connect after $attempts attempts';
    stderr.writeln(chalk.brightRed(msg));
    throw UnAuthenticatedException(msg);
  }
  stderr.writeln(chalk.brightGreen('Connected'));
  // Get the AtClient which the onboardingService just authenticated
  return AtClientManager.getInstance().atClient;
}
