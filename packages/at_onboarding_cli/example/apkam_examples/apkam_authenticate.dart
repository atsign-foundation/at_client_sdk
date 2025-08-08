import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

import '../util/custom_arg_parser.dart';

Future<void> main(List<String> args) async {
  AtSignLogger.root_level = 'info';
  final argResults = CustomArgParser(getArgParser()).parse(args);

  final atSign = argResults['atsign'];
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..namespace =
        'wavi' // unique identifier that can be used to identify data from your app
    ..atKeysFilePath = argResults['atKeysPath']
    ..rootDomain = 'vip.ve.atsign.zone';
  AtOnboardingService? onboardingService = AtOnboardingServiceImpl(
      atSign, atOnboardingPreference,
      enrollmentId: _getEnrollmentIdFromKeysFile(argResults['atKeysPath']));

  await onboardingService.authenticate();
  AtLookUp? atLookup = onboardingService.atLookUp;
  AtClient? client = onboardingService.atClient;
  print(await client?.getKeys());
  print(await atLookup?.scan(regex: 'publickey'));
  await onboardingService.close();
}

getArgParser() {
  return ArgParser()
    ..addOption('atsign',
        abbr: 'a', help: 'the atsign you would like to auth with')
    ..addOption('atKeysPath', abbr: 'k', help: 'location of your .atKeys file')
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
}

String _getEnrollmentIdFromKeysFile(String keysFilePath) {
  String atAuthData = File(keysFilePath).readAsStringSync();
  final enrollmentId = jsonDecode(atAuthData)[AtConstants.enrollmentId];
  print('**** enrollmentId: $enrollmentId');
  return enrollmentId;
}
