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

Future<AtClient> createAtClient(
    {required String atSign,
    String? atKeysFilePath,
    String? rootDomain,
    String? passPhrase}) async {
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
  
  // Parse rootServer to extract domain and port
  String parsedRootDomain;
  int parsedRootPort;
  bool isUsingProxy;
  
  if (rootServer.startsWith('proxy:')) {
    isUsingProxy = true;
    String serverPart = rootServer.substring(6); // Remove 'proxy:' prefix
    
    if (serverPart.contains(':')) {
      // proxy:host:port format
      List<String> parts = serverPart.split(':');
      parsedRootDomain = 'proxy:${parts[0]}';
      parsedRootPort = int.tryParse(parts[1]) ?? 64;
    } else {
      // proxy:host format
      parsedRootDomain = rootServer;
      parsedRootPort = 64;
    }
  } else if (rootServer.contains(':')) {
    // host:port format
    isUsingProxy = false;
    List<String> parts = rootServer.split(':');
    parsedRootDomain = parts[0];
    parsedRootPort = int.tryParse(parts[1]) ?? 64;
  } else {
    // host format
    isUsingProxy = false;
    parsedRootDomain = rootServer;
    parsedRootPort = 64;
  }
  
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..atKeysFilePath = atKeysFilePathToUse
    ..namespace = nameSpace
    ..rootDomain = parsedRootDomain
    ..rootPort = parsedRootPort
    ..passPhrase = passPhrase
    ..hiveStoragePath = localStoragePathToUse
    ..commitLogPath = commitLogStoragePathToUse
    ..downloadPath = downloadPathToUse
    ..isUsingProxy = isUsingProxy;

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
