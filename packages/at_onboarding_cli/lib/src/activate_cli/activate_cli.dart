import 'dart:io';

import 'package:args/args.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';

@Deprecated('Use auth_cli')
Future<void> main(List<String> arguments) async {
  int exitCode = await wrappedMain(arguments);
  exit(exitCode);
}

@Deprecated('Use auth_cli')
Future<int> wrappedMain(List<String> arguments) async {
  //defaults
  String rootServer = 'root.atsign.org';
  String registrarUrl = 'my.atsign.com';
  AtSignLogger.root_level = 'severe';
  //get atSign and CRAM key from args
  final parser = ArgParser()
    ..addOption('atsign', abbr: 'a', help: 'atSign to activate')
    ..addOption('cramkey', abbr: 'c', help: 'CRAM key', mandatory: false)
    ..addOption('appName',
        abbr: 'p',
        help: 'application name that identifies the client',
        mandatory: false,
        defaultsTo: 'testapp')
    ..addOption('deviceName',
        abbr: 'd',
        help: 'device name on which the application is running',
        mandatory: false,
        defaultsTo: 'testdevice')
    ..addOption('rootServer',
        abbr: 'r',
        help: 'root server\'s domain name (deprecated, use --root-server instead)',
        defaultsTo: rootServer,
        mandatory: false)
    ..addOption('root-server',
        help: 'Root server domain (e.g., root.atsign.org). Replaces deprecated --rootServer',
        defaultsTo: rootServer,
        mandatory: false)
    ..addOption('registrarUrl',
        abbr: 'g',
        help: 'url to the registrar api',
        mandatory: false,
        defaultsTo: registrarUrl)
    ..addFlag('help', abbr: 'h', help: 'Usage instructions', negatable: false);
  ArgResults argResults = parser.parse(arguments);

  if (argResults.wasParsed('help')) {
    stdout.writeln(parser.usage);
    return 0;
  }

  if (!argResults.wasParsed('atsign')) {
    stderr.writeln(
        '--atsign (or -a) is required. Run with --help (or -h) for more.');
    throw IllegalArgumentException('atSign is required');
  }

  return await activate(argResults);
}

@Deprecated('Use auth_cli')
Future<int> activate(ArgResults argResults,
    {AtOnboardingService? atOnboardingService}) async {
  // Handle both old and new root server arguments with preference for new one
  bool newRootServerProvided = argResults.wasParsed('root-server');
  bool oldRootServerProvided = argResults.wasParsed('rootServer');
  
  String finalRootServer;
  if (newRootServerProvided) {
    // User explicitly provided --root-server
    finalRootServer = argResults['root-server'];
    if (oldRootServerProvided) {
      // Both explicitly provided, warn user
      stderr.writeln('Warning: Both --rootServer and --root-server provided. Using --root-server value: $finalRootServer');
      stderr.writeln('Note: --rootServer is deprecated, please use --root-server instead.');
    }
  } else if (oldRootServerProvided) {
    // User explicitly provided --rootServer (deprecated)
    finalRootServer = argResults['rootServer'];
    stderr.writeln('Warning: --rootServer is deprecated, please use --root-server instead.');
  } else {
    // Neither provided explicitly, use default
    finalRootServer = 'root.atsign.org';
  }

  stdout.writeln('[Information] Root server is $finalRootServer');
  stdout.writeln(
      '[Information] Registrar url provided is ${argResults['registrarUrl']}');
  //onboarding preference builder can be used to set onboardingService parameters
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..rootDomain = finalRootServer
    ..registrarUrl = argResults['registrarUrl']
    ..cramSecret =
        argResults.wasParsed('cramkey') ? argResults['cramkey'] : null
    ..appName = argResults['appName']
    ..deviceName = argResults['deviceName'];
  //onboard the atSign
  atOnboardingService ??=
      AtOnboardingServiceImpl(argResults['atsign'], atOnboardingPreference);
  stdout.writeln(
      '[Information] Activating your atSign. This may take up to 2 minutes.');
  int retCode = 0;
  try {
    await atOnboardingService.onboard();
  } on InvalidDataException catch (e) {
    stderr.writeln(
        '[Error] Activation failed. Invalid data provided by user. Please try again\nCause: ${e.message}');
    retCode = 1;
  } on InvalidRequestException catch (e) {
    stderr.writeln(
        '[Error] Activation failed. Invalid data provided by user. Please try again\nCause: ${e.message}');
    retCode = 2;
  } on AtActivateException catch (e) {
    stdout.writeln('[Error] ${e.message}');
    retCode = 3;
  } catch (e) {
    stderr.writeln(
        '[Error] Activation failed. It looks like something went wrong on our side.\n'
        'Please try again or contact support@atsign.com\nCause: $e');
    retCode = 4;
  } finally {
    await atOnboardingService.close();
  }
  return retCode;
}
