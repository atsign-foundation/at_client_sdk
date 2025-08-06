import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/util/create_at_client_cli.dart';
import 'package:at_onboarding_cli/src/util/print_full_parser_usage.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:duration/duration.dart';
import 'package:meta/meta.dart';

import '../util/onboarding_util.dart';
import 'auth_cli_arg_validation.dart';
import 'auth_cli_args.dart';

final AtSignLogger logger = AtSignLogger(' CLI ');

final aca = AuthCliArgs();

Directory? storageDir;

void deleteStorage() {
  // Windows will not let us delete files that are open
  // so will will ignore this step and leave them in %localappdata%\Temp
  if (!Platform.isWindows) {
    if (storageDir != null) {
      if (storageDir!.existsSync()) {
        // stderr.writeln('${DateTime.now()} : Cleaning up temporary files');
        storageDir!.deleteSync(recursive: true);
      }
    }
  }
}

Future<int> main(List<String> arguments) async {
  AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;
  try {
    return await wrappedMain(arguments);
  } on ArgumentError catch (e) {
    stderr.writeln('Invalid argument: ${e.message}');
    aca.parser.printAllCommandsUsage();
    return 1;
  } catch (e) {
    stderr.writeln('Error: $e');
    aca.parser.printAllCommandsUsage();
    return 1;
  } finally {
    try {
      deleteStorage();
    } catch (_) {}
  }
}

Future<int> wrappedMain(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln('You must supply a command.');
    aca.parser.printAllCommandsUsage(showSubCommandParams: false);
    stderr.writeln('\n'
        'Use --help or -h flag to show full usage of all commands'
        '\n');
    return 1;
  }

  final first = arguments.first;
  if (first.startsWith('-') && first != '-h' && first != '--help') {
    // no command found ... legacy ... insert 'onboard' as the command
    arguments = ['onboard', ...arguments];
  }

  final ArgResults topLevelResults;
  try {
    topLevelResults = aca.parser.parse(arguments);
  } catch (e) {
    stderr.writeln('\n$e');
    stderr.writeln();
    aca.parser.printAllCommandsUsage();
    return 1;
  }

  if (topLevelResults.wasParsed(AuthCliArgs.argNameHelp)) {
    aca.sharedArgsParser
        .printAllCommandsUsage(header: 'Arguments common to all commands: ');
    aca.parser.printAllCommandsUsage(showSubCommandParams: true);
    stderr.writeln();
    return 0;
  }

  final AuthCliCommand cliCommand;
  try {
    cliCommand = AuthCliCommand.values.byName(arguments.first);
  } catch (e) {
    throw ArgumentError('Unknown command: ${arguments.first}');
  }

  if (topLevelResults.command == null) {
    throw ArgumentError('No command was parsed');
  }

  ArgResults commandArgResults = topLevelResults.command!;
  if (commandArgResults.name != cliCommand.name) {
    throw ArgumentError('detected command ${cliCommand.name}'
        ' but parsed command ${commandArgResults.name} ');
  }

  // Parse the command options
  ArgParser commandParser = aca.parser.commands[cliCommand.name]!;

  if (commandArgResults.wasParsed(AuthCliArgs.argNameHelp)) {
    commandParser.printAllCommandsUsage(
        header: 'Usage: ${cliCommand.name}', showSubCommandParams: true);
    aca.sharedArgsParser.printAllCommandsUsage();
    stderr.writeln('\n${cliCommand.usage}\n');
    return 0;
  }

  // Parse the log levels and act accordingly
  AtSignLogger.root_level = 'shout';

  if (commandArgResults.wasParsed(AuthCliArgs.argNameVerbose)) {
    AtSignLogger.root_level = 'info';
  }
  if (commandArgResults.wasParsed(AuthCliArgs.argNameDebug)) {
    AtSignLogger.root_level = 'finest';
  }

  // Execute the command
  try {
    switch (cliCommand) {
      case AuthCliCommand.help:
        aca.parser.printAllCommandsUsage(showSubCommandParams: true);
        break;

      case AuthCliCommand.status:
        return await status(commandArgResults);

      case AuthCliCommand.onboard:
        // First time an app is connecting to an atServer.
        // Authenticate with cram secret
        // then set PKAM keys
        // then authenticate with PKAM to verify
        // and then delete the cram secret
        // Write keys to the usual output file @atSign_keys.atKeys
        await onboard(commandArgResults);

      case AuthCliCommand.spp:
        // set a semi-permanent passcode for this atSign. This is a passcode
        // which enrolling apps can provide which will signal that this is a
        // real enrollment request and will be accepted by the atServer.
        // Note that enrollment requests always require approval from an
        // already-authenticated authorized atClient - the passcode on
        // enrollment requests is used solely to defend against ddos attacks
        // where users are bombarded with spurious enrollment requests.
        await setSpp(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.otp:
        // generate a one-time-passcode for this atSign. This is a passcode
        // which enrolling apps can provide which will signal that this is a
        // real enrollment request and will be accepted by the atServer.
        // Note that enrollment requests always require approval from an
        // already-authenticated authorized atClient - the passcode on
        // enrollment requests is used solely to defend against ddos attacks
        // where users are bombarded with spurious enrollment requests.
        await generateOtp(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.interactive:
        // Interactive session for various enrollment management activities:
        // - listing, approving, denying and revoking enrollments
        // - setting spp, generating otp, etc
        await interactive(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.list:
        await list(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.fetch:
        await fetch(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.approve:
        await approve(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.auto:
        await autoApprove(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.deny:
        await deny(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.revoke:
        await revoke(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.enroll:
        // App which doesn't have auth keys and is not the first app.
        // Send an enrollment request which has to be approved by an existing
        // app which has permissions to approve enrollment requests.
        // Write keys to @atSign_keys.atKeys IFF it doesn't already exist; if
        // it does exist, then write to @atSign_appName_deviceName_keys.atKeys
        await enroll(commandArgResults);

      case AuthCliCommand.unrevoke:
        await unrevoke(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));

      case AuthCliCommand.delete:
        await deleteEnrollment(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain:
                    commandArgResults[AuthCliArgs.argNameAtDirectoryFqdn],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase]));
    }
  } on ArgumentError catch (e) {
    stderr
        .writeln('Argument error for command ${cliCommand.name}: ${e.message}');
    commandParser.printAllCommandsUsage(
      header: 'Usage: ${cliCommand.name}',
    );
    aca.sharedArgsParser.printAllCommandsUsage();
    return 1;
  } catch (e) {
    await Future.delayed(Duration(milliseconds: 10));
    stderr.writeln();
    stderr.writeln();
    final bolded = chalk.bold(chalk.brightRed('ERROR: ${cliCommand.name}'));

    stderr.writeln('$bolded : $e');
    stderr.writeln();
    stderr.writeln('Please try again or contact support@atsign.com');
    return 1;
  }

  return 0;
}

/// Check the status of an atSign - returns
///  - 4 if the atDirectory cannot be reached
///  - 3 if atDirectory is reachable but the atSign does not exist
///  - 2 if the atSign exists but the atServer cannot be reached
///  - 1 if the atServer is reachable but there is no `public:publickey@<atsign>`
///  - 0 if the atServer is reachable and `public:publickey@<atsign>` exists
Future<int> status(ArgResults ar) async {
  String atSign = AtUtils.fixAtSign(ar[AuthCliArgs.argNameAtSign]);

  SecondaryAddressFinder saf = CacheableSecondaryAddressFinder(
      ar[AuthCliArgs.argNameAtDirectoryFqdn], 64);
  try {
    await saf.findSecondary(atSign);
  } on SecondaryNotFoundException {
    stderr.writeln('returning 3: atDirectory has no record for $atSign');
    return 3;
  } catch (e) {
    stderr.writeln('returning 4: Caught ${e.runtimeType} : $e');
    return 4;
  }

  String? pk;
  try {
    AtLookUp al = AtLookupImpl(
      atSign,
      ar[AuthCliArgs.argNameAtDirectoryFqdn],
      64,
    );
    try {
      pk = await al.executeCommand('lookup:publickey$atSign\n', auth: false);
    } on AtLookUpException catch (e) {
      final e1 = AtExceptionUtils.get(e.errorCode ?? '', e.errorMessage ?? '');
      throw e1;
    }
  } on SecondaryServerConnectivityException catch (e) {
    stderr.writeln('returning 2: atServer cannot be reached $atSign ($e)');
    return 2;
  } on KeyNotFoundException catch (e) {
    stderr.writeln('returning 1: $e');
    return 1;
  } catch (e) {
    stderr.writeln('returning 2: Caught unexpected ${e.runtimeType} : $e');
    return 2;
  }

  if (pk == null || !pk.startsWith("data:")) {
    stderr.writeln('returning 1: response was $pk');
    return 1;
  }

  stderr.writeln('returning 0: found public:publickey$atSign OK');
  return 0;
}

/// When a cramSecret arg is not supplied, we first use the registrar API
/// to send an OTP to the user and then use that OTP to obtain the cram
/// secret from the registrar.
@visibleForTesting
Future<bool> onboard(ArgResults argResults, {AtOnboardingService? svc}) async {
  svc ??= createOnboardingService(argResults);
  logger
      .info('Root server is ${argResults[AuthCliArgs.argNameAtDirectoryFqdn]}');
  logger.info(
      'Registrar url provided is ${argResults[AuthCliArgs.argNameRegistrarFqdn]}');

  stderr.writeln(
      '${chalk.blue('[Information]')} Onboarding your atSign. This may take up to 2 minutes.');
  try {
    if (argResults[AuthCliArgs.argNameAllowBadRegistrarCerts]) {
      logger.shout('*************');
      logger.shout('************* Will ignore bad (expired, invalid, etc)'
          ' registrar certificates');
      logger.shout('*************');
      OnboardingUtil.allowBadCertificates = true;
    }
    await svc.onboard(
      maxRetries: int.parse(argResults[AuthCliArgs.argNameMaxRetries]),
      retryInterval: AtOnboardingService.defaultActivationCheckInterval,
    );
    stderr.writeln();
    return true;
  } catch (e) {
    await Future.delayed(Duration(milliseconds: 10));
    throw ('Onboarding failed : $e');
  }
}

String parseServerResponse(String? response) {
  if (response != null && response.startsWith('data:')) {
    return response.replaceFirst(RegExp(r'^data:'), '');
  } else {
    throw ('Unexpected server response: $response');
  }
}

/// auth enroll : require atSign, app name, device name, otp [, atKeys path]
///     If atKeys file doesn't exist, then this is a new enrollment
///     If it does exist, then the enrollment request has been made and we need
///         to try to auth, and act appropriately on the atServer response
@visibleForTesting
Future<bool> enroll(ArgResults argResults, {AtOnboardingService? svc}) async {
  if (!argResults.wasParsed(AuthCliArgs.argNameAtKeys)) {
    throw ArgumentError('The --${AuthCliArgs.argNameAtKeys} option is'
        ' mandatory for the "enroll" command');
  }

  File f = File(argResults[AuthCliArgs.argNameAtKeys]);

  if (f.existsSync()) {
    throw StateError('Error: atKeys file ${f.path} already exists');
  }

  if (!canCreateFile(f)) {
    throw StateError('Error: Unable to open $f for writing');
  }

  svc ??= createOnboardingService(argResults);

  Map<String, String> namespaces = {};
  String nsArg = argResults[AuthCliArgs.argNameNamespaceAccessList];
  List<String> nsList = nsArg.split(',');
  for (String item in nsList) {
    List<String> l = item.split(':');
    String namespace = l[0].replaceAll('"', '').trim();
    String permission = l[1].replaceAll('"', '').trim();
    namespaces[namespace] = permission;
  }

  // If apkam Keys expiry is not set, then APKAM keys should lives forever.
  // Therefore set to 0ms (0 milliseconds) and TTL will not be set.
  String apkamKeysExpiry = argResults[AuthCliArgs.argNameExpiry] ?? '0ms';
  AtEnrollmentResponse er = await svc.sendEnrollRequest(
      argResults[AuthCliArgs.argNameAppName],
      argResults[AuthCliArgs.argNameDeviceName],
      argResults[AuthCliArgs.argNamePasscode],
      namespaces,
      apkamKeysExpiryDuration: parseDuration(apkamKeysExpiry));
  stdout.writeln('Enrollment ID: ${er.enrollmentId}');

  stderr.writeln('Waiting for approval; will check every 10 seconds');
  await svc.awaitApproval(er,
      retryInterval: AtOnboardingService.defaultApkamRetryInterval,
      logProgress: true,
      maxRetries: int.parse(argResults[AuthCliArgs.argNameMaxRetries]));

  stderr.writeln('Creating atKeys file');
  await svc.createAtKeysFile(er, allowOverwrite: false);

  return true;
}

/// Checks if the specified [file] is writable.
///
/// This function attempts to create the directories for the given [file] if they do not exist,
/// and then tries to open the file in write mode to verify write permissions.
/// If the file can be opened for writing, it is immediately closed and deleted.
///
/// Returns:
/// - `true` if the file is writable, or
/// - `false` if the file is not writable due to existing files, lack of permissions,
///   or any other exceptions encountered during the process.
///
/// [file]: The [File] instance to check for write access.
///
/// Exceptions:
/// - If the file does not have write permissions, a [PathAccessException] is caught, and an error message is printed to stderr.
/// - Any other exceptions are caught and logged, indicating a failure to determine write access.
@visibleForTesting
bool canCreateFile(File file) {
  try {
    // If the directories do not exist, create them.
    // "recursive" is set to true to ensure that any missing parent directories are created.
    // "exclusive" is set to true to prevent creation of file if it already exists.
    file.createSync(recursive: true, exclusive: true);
    // Try opening the file in write mode, which requires write permissions
    RandomAccessFile raf = file.openSync(mode: FileMode.write);
    raf.closeSync();
    // In [AtOnboardingServiceImpl._generateAtKeysFile] method, there is a check which returns error
    // if the file already exists. Therefore, delete the file here after checking for write permissions.
    // This does not delete the existing file. Deletes only if the new file is created to verify write permissions.
    file.deleteSync();
    return true;
  } on PathExistsException {
    stderr.writeln('Error : atKeys file ${file.path} already exists');
    rethrow;
  } on PathAccessException {
    stderr.writeln(
        'Error : atKeys file ${file.path} does not have write permissions');
    return false;
  } catch (e) {
    // If any exception occurs, we assume the file is not writable
    stderr.writeln('Error in writing to atKeys file: ${e.toString()}');
    return false;
  }
}

@visibleForTesting
Future<void> setSpp(ArgResults argResults, AtClient atClient) async {
  String spp = argResults[AuthCliArgs.argNameSpp];
  String? sppExpiry = argResults[AuthCliArgs.argNameExpiry];
  if (invalidSpp(spp)) {
    throw ArgumentError(invalidSppMsg);
  }

  StringBuffer sppCommandBuffer = StringBuffer()..append('otp:put:$spp');
  if (sppExpiry != null && sppExpiry.isNotEmpty) {
    sppCommandBuffer.append(':ttl:${parseDuration(sppExpiry).inMilliseconds}');
  }
  sppCommandBuffer.append('\n');

  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;
  // send command 'otp:put:$spp'
  String? response =
      await atLookup.executeCommand(sppCommandBuffer.getData()!, auth: true);

  stdout.writeln('Server response: $response');
}

@visibleForTesting
Future<void> generateOtp(ArgResults argResults, AtClient atClient) async {
  String? otpExpiry = argResults[AuthCliArgs.argNameExpiry];
  StringBuffer otpCommandBuffer = StringBuffer()..append('otp:get');
  if (otpExpiry != null && otpExpiry.isNotEmpty) {
    otpCommandBuffer.append(':ttl:${parseDuration(otpExpiry).inMilliseconds}');
  }
  otpCommandBuffer.append('\n');

  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;
  // send command 'otp:get[:ttl:$ttl]'
  String? response =
      await atLookup.executeCommand(otpCommandBuffer.getData()!, auth: true);
  if (response != null && response.startsWith('data:')) {
    stdout.writeln(response.substring('data:'.length));
  } else {
    stderr.writeln('Failed to generate OTP: server response was $response');
  }
}

/// Only usable if there are atKeys already available.
/// All commands available same as the CLI as a whole, except for
/// 'onboard' and 'enroll'
Future<void> interactive(ArgResults argResults, AtClient atClient) async {
  // TODO Factor out code which is shared between here and main()
  while (true) {
    stderr.write(r'$ ');
    List<String> arguments = stdin.readLineSync()!.split(RegExp(r'\s'));

    final AuthCliCommand cliCommand;
    try {
      cliCommand = AuthCliCommand.values.byName(arguments.first);
    } catch (e) {
      stderr.writeln('Unknown command: ${arguments.first}');
      continue;
    }

    final ArgResults topLevelResults = aca.parser.parse(arguments);

    if (topLevelResults.wasParsed(AuthCliArgs.argNameHelp)) {
      aca.sharedArgsParser
          .printAllCommandsUsage(header: 'Arguments common to all commands: ');
      aca.parser.printAllCommandsUsage(showSubCommandParams: true);
      stderr.writeln();
      continue;
    }

    if (topLevelResults.command == null) {
      stderr.writeln('No command was parsed');
      continue;
    }

    ArgResults commandArgResults = topLevelResults.command!;
    if (commandArgResults.name != cliCommand.name) {
      stderr.writeln('detected command ${cliCommand.name}'
          ' but parsed command ${commandArgResults.name} ');
      continue;
    }

    // Parse the command options
    ArgParser commandParser = aca.parser.commands[cliCommand.name]!;

    if (commandArgResults.wasParsed(AuthCliArgs.argNameHelp)) {
      commandParser.printAllCommandsUsage(
          header: 'Usage: ${cliCommand.name}', showSubCommandParams: true);
      stderr.writeln('\n${cliCommand.usage}\n');
      continue;
    }

    // Execute the command
    try {
      switch (cliCommand) {
        case AuthCliCommand.help:
          aca.parser.printAllCommandsUsage(showSubCommandParams: true);

        case AuthCliCommand.onboard:
        case AuthCliCommand.interactive:
        case AuthCliCommand.status:
        case AuthCliCommand.enroll:
          stderr.writeln('The "${cliCommand.name}" command'
              ' may not be used in interactive session');

        case AuthCliCommand.spp:
          await setSpp(commandArgResults, atClient);

        case AuthCliCommand.otp:
          await generateOtp(commandArgResults, atClient);

        case AuthCliCommand.list:
          await list(commandArgResults, atClient);

        case AuthCliCommand.fetch:
          await fetch(commandArgResults, atClient);

        case AuthCliCommand.approve:
          await approve(commandArgResults, atClient);

        case AuthCliCommand.auto:
          await autoApprove(commandArgResults, atClient);

        case AuthCliCommand.deny:
          await deny(commandArgResults, atClient);

        case AuthCliCommand.revoke:
          await revoke(commandArgResults, atClient);

        case AuthCliCommand.unrevoke:
          await unrevoke(commandArgResults, atClient);

        case AuthCliCommand.delete:
          await deleteEnrollment(commandArgResults, atClient);
      }
    } on ArgumentError catch (e) {
      stderr.writeln(
          'Argument error for command ${cliCommand.name}: ${e.message}');
      commandParser.printAllCommandsUsage(header: 'Usage: ${cliCommand.name}');
    }
  }
}

Future<Map> _list(
  String? statusFilter,
  AtLookUp atLookup, {
  String? arx,
  String? drx,
}) async {
  String command = 'enroll:list';
  if (statusFilter != null) {
    command += ':{"enrollmentStatusFilter":["$statusFilter"]}';
  }
  String rawResponse = (await atLookup.executeCommand(
    '$command\n',
    auth: true,
  ))!;

  RegExp? ar;
  RegExp? dr;
  if (arx != null) {
    ar = RegExp(arx);
  }
  if (drx != null) {
    dr = RegExp(drx);
  }
  if (rawResponse.startsWith('data:')) {
    rawResponse = rawResponse.substring(rawResponse.indexOf('data:') + 5);
    Map unfiltered = jsonDecode(rawResponse);
    Map filtered = {};
    for (final String ek in unfiltered.keys) {
      final e = unfiltered[ek];
      String appName = e['appName'] as String;
      if (ar != null) {
        if (!ar.hasMatch(appName)) {
          continue;
        }
      }
      String deviceName = e['deviceName'] as String;
      if (dr != null) {
        if (!dr.hasMatch(deviceName)) {
          continue;
        }
      }
      filtered[ek.substring(0, ek.indexOf('.'))] = e;
    }
    stdout.writeln("Found ${filtered.length} matching enrollment records");
    return filtered;
  } else {
    throw Exception('Unexpected server response: $rawResponse');
  }
}

Future<void> list(ArgResults ar, AtClient atClient) async {
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  String? statusFilter = ar[AuthCliArgs.argNameEnrollmentStatus];
  String? arx = ar[AuthCliArgs.argNameAppNameRegex];
  String? drx = ar[AuthCliArgs.argNameDeviceNameRegex];

  Map json = await _list(statusFilter, atLookup, arx: arx, drx: drx);
  stdout.write('Enrollment ID'.padRight(38));
  stdout.write('Status'.padRight(10));
  stdout.write('AppName'.padRight(20));
  stdout.write('DeviceName'.padRight(38));
  stdout.writeln('Namespaces');
  for (final eId in json.keys) {
    final e = json[eId] as Map;
    final String status = e['status'];
    final String appName = e['appName'];
    final String deviceName = e['deviceName'];
    final namespaces = e['namespace'];
    stdout.writeln('${eId.padRight(38)}'
        '${status.padRight(10)}'
        '${appName.padRight(20)}'
        '${deviceName.padRight(38)}'
        '$namespaces');
  }
}

Future<Map?> _fetch(String eId, AtLookUp atLookup) async {
  EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
    ..operation = EnrollOperationEnum.fetch
    ..enrollmentId = eId;
  String? response = await atLookup.executeVerb(enrollVerbBuilder);

  response = parseServerResponse(response);
  // response is a Map
  return jsonDecode(response);
}

Future<void> fetch(ArgResults argResults, AtClient atClient) async {
  String eId = argResults[AuthCliArgs.argNameEnrollmentId];
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  Map? er = await _fetch(eId, atLookup);
  if (er == null) {
    stderr.writeln('Enrollment ID $eId not found');
    return;
  } else {
    stdout.writeln('Fetched enrollment OK: $er');
  }
}

Future<Map> _fetchOrListAndFilter(
  AtLookUp atLookup,
  String statusFilter, {
  String? eId,
  String? arx,
  String? drx,
}) async {
  if (eId == null && arx == null && drx == null) {
    throw ArgumentError('At least one of'
        ' --${AuthCliArgs.argNameEnrollmentId},'
        ' --${AuthCliArgs.argNameAppNameRegex}'
        ' or --${AuthCliArgs.argNameDeviceNameRegex}'
        ' must be provided');
  }

  Map enrollmentMap = {};
  if (eId != null) {
    // First fetch the enrollment request
    Map? er = await _fetch(eId, atLookup);
    if (er == null) {
      stderr.writeln('Enrollment ID $eId not found');
    }
    enrollmentMap[eId] = er;
  } else {
    enrollmentMap = await _list(
      statusFilter,
      atLookup,
      arx: arx,
      drx: drx,
    );
  }
  return enrollmentMap;
}

Future<int> approve(ArgResults ar, AtClient atClient, {int? limit}) async {
  int approved = 0;
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  Map toApprove = await _fetchOrListAndFilter(
    atLookup,
    EnrollmentStatus.pending.name, // must be status pending
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toApprove.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return approved;
  }

  // Iterate through the requests, approve each one
  for (String eId in toApprove.keys) {
    Map er = toApprove[eId];
    stdout.writeln('Approving enrollmentId $eId'
        ' with appName "${er['appName']}"'
        ' and deviceName "${er['deviceName']}"');
    // Then make a 'decision' object using data from the enrollment request
    EnrollmentRequestDecision decision = EnrollmentRequestDecision.approved(
        ApprovedRequestDecisionBuilder(
            enrollmentId: eId,
            encryptedAPKAMSymmetricKey: er['encryptedAPKAMSymmetricKey']));

    // Finally call approve method via an AtEnrollment object
    final response = await atAuthBase
        .atEnrollment(atClient.getCurrentAtSign()!)
        .approve(decision, atLookup);

    stdout.writeln('Server response: $response');

    approved++;

    if (limit != null && approved >= limit) {
      return approved;
    }
  }
  return approved;
}

Future<int> autoApprove(ArgResults ar, AtClient atClient) async {
  int approved = 0;
  int limit = int.parse(ar[AuthCliArgs.argNameLimit]);
  String? arx = ar[AuthCliArgs.argNameAppNameRegex];
  String? drx = ar[AuthCliArgs.argNameDeviceNameRegex];
  bool approveExisting = ar[AuthCliArgs.argNameAutoApproveExisting];

  if (arx == null && drx == null) {
    throw IllegalArgumentException(
        'You must supply ${AuthCliArgs.argNameAppNameRegex}'
        ' and/or ${AuthCliArgs.argNameDeviceNameRegex}');
  }

  if (approveExisting) {
    // Start by approving any which match and are already there
    stdout.writeln('Approving any requests already there which are a match');
    approved = await approve(ar, atClient, limit: limit);
    stdout.writeln();
  }

  // If we've already approved our limit then we're done
  if (approved >= limit) {
    return approved;
  }

  Completer completer = Completer();

  RegExp? appRegex;
  RegExp? deviceRegex;
  if (arx != null) {
    appRegex = RegExp(arx);
  }
  if (drx != null) {
    deviceRegex = RegExp(drx);
  }

  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  // listen for enrollment requests
  stdout.writeln('Listening for new enrollment requests');

  final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage', shouldDecrypt: false);

  final subscription = stream.listen((AtNotification n) async {
    if (completer.isCompleted) {
      return; // Don't handle any more if we're already done
    }

    String eId = n.key.substring(0, n.key.indexOf('.'));

    final er = jsonDecode(n.value!);
    stdout.writeln('Got enrollment request ID $eId'
        ' with appName "${er['appName']}"'
        ' and deviceName "${er['deviceName']}"');

    // check the request matches our params
    String appName = er['appName'];
    String deviceName = er['deviceName'];
    if ((appRegex?.hasMatch(appName) ?? true) &&
        (deviceRegex?.hasMatch(deviceName) ?? true)) {
      // request matched, let's approve it
      stdout.writeln('Approving enrollment request'
          ' which matched the regex filters'
          ' (app: "$arx" and device: "$drx" respectively)');

      EnrollmentRequestDecision decision = EnrollmentRequestDecision.approved(
          ApprovedRequestDecisionBuilder(
              enrollmentId: eId,
              encryptedAPKAMSymmetricKey: er['encryptedAPKAMSymmetricKey']));

      // Finally call approve method via an AtEnrollment object
      final response = await atAuthBase
          .atEnrollment(atClient.getCurrentAtSign()!)
          .approve(decision, atLookup);
      stdout.writeln('Approval successful.\n'
          '\tResponse: $response');

      // increment approved count
      approved++;

      // check approved vs limit
      if (approved >= limit) {
        // if reached limit, complete the future
        stdout
            .writeln('Approved $approved requests - limit was $limit - done.');
        completer.complete();
      }
    } else {
      stdout.writeln('Ignoring enrollment request'
          ' which does not match the regex filters'
          ' (app: "$arx" and device: "$drx" respectively)');
    }
    stdout.writeln();
  });

  // await future then cancel the subscription
  await completer.future;
  await subscription.cancel();

  return approved;
}

Future<void> deny(ArgResults ar, AtClient atClient) async {
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  Map toDeny = await _fetchOrListAndFilter(
    atLookup,
    EnrollmentStatus.pending.name, // must be status pending
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toDeny.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  // Iterate through the requests, deny each one
  for (String eId in toDeny.keys) {
    stdout.writeln('Denying enrollmentId $eId');
    EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
      ..operation = EnrollOperationEnum.deny
      ..enrollmentId = eId;
    String? response = await atLookup.executeVerb(enrollVerbBuilder);
    stdout.writeln('Server response: $response');
  }
}

Future<void> revoke(ArgResults ar, AtClient atClient) async {
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  Map toRevoke = await _fetchOrListAndFilter(
    atLookup,
    EnrollmentStatus.approved.name, // must be status approved
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toRevoke.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  // Iterate through the requests, revoke each one
  for (String eId in toRevoke.keys) {
    stdout.writeln('Revoking enrollmentId $eId');
    // 'enroll:revoke:{"enrollmentid":"$enrollmentId"}'
    String? response = await atLookup
        .executeCommand('enroll:revoke:{"enrollmentId":"$eId"}\n', auth: true);
    stdout.writeln('Server response: $response');
  }
}

Future<void> unrevoke(ArgResults ar, AtClient atClient) async {
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;

  Map toUnRevoke = await _fetchOrListAndFilter(
    atLookup,
    EnrollmentStatus.approved.name, // must be status approved
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toUnRevoke.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  for (String eId in toUnRevoke.keys) {
    stdout.writeln('Un-Revoking enrollmentId $eId');
    String? response = await atLookup.executeCommand(
        'enroll:unrevoke:{"enrollmentId":"$eId"}\n',
        auth: true);
    stdout.writeln('Server response: $response');
  }
}

Future<void> deleteEnrollment(ArgResults ar, AtClient atClient) async {
  AtLookUp atLookup = atClient.getRemoteSecondary()!.atLookUp;
  String eId = ar[AuthCliArgs.argNameEnrollmentId];
  EnrollVerbBuilder enrollVerbBuilder = EnrollVerbBuilder()
    ..enrollmentId = eId
    ..operation = EnrollOperationEnum.delete;
  stdout.writeln('Sending delete request');
  String? response = await atLookup.executeVerb(enrollVerbBuilder);
  response = parseServerResponse(response);
  stdout.writeln('Server response: $response');
}

@visibleForTesting
AtOnboardingService createOnboardingService(ArgResults ar) {
  String atSign = AtUtils.fixAtSign(ar[AuthCliArgs.argNameAtSign]);
  AtOnboardingPreference atOnboardingPreference = AtOnboardingPreference()
    ..rootDomain = ar[AuthCliArgs.argNameAtDirectoryFqdn]
    ..registrarUrl = ar[AuthCliArgs.argNameRegistrarFqdn]
    ..cramSecret = ar[AuthCliArgs.argNameCramSecret]
    ..atKeysFilePath = ar[AuthCliArgs.argNameAtKeys]
    ..passPhrase = ar[AuthCliArgs.argNamePassPhrase]
    ..hashingAlgoType =
        HashingAlgoType.fromString(ar[AuthCliArgs.argNameHashingAlgoType]);

  final impl = AtOnboardingServiceImpl(atSign, atOnboardingPreference);
  String lastProgressEventType = '';
  int pad = 10;
  impl.subscribeProgress().listen((pe) {
    if (pe.group.isNotEmpty && pe.group != lastProgressEventType) {
      stderr.writeln();
    }
    if (pe.group.length > pad) {
      pad = pe.group.length;
    }
    lastProgressEventType = pe.group;
    String output = '${pe.type.chalkFn(pe.group.padLeft(pad))} : ${pe.msg}'
        .replaceAll('\n', '\\n')
        .replaceAll('\t', ' ');
    int viewableLength = '${pe.group.padLeft(pad)} : ${pe.msg}'
        .replaceAll('\n', '\\n')
        .replaceAll('\t', ' ')
        .length;
    int diff = output.length - viewableLength;
    if (stdout.hasTerminal && viewableLength > (stdout.terminalColumns - 3)) {
      output = '${output.substring(0, stdout.terminalColumns - 3 + diff)}...';
    }
    stderr.write('\r\x1b[K$output');
  });

  return impl;
}
