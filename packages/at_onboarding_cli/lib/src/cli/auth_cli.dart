import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_onboarding_cli/src/util/at_file_util.dart';
import 'package:at_onboarding_cli/src/util/home_directory_util.dart';
import 'package:at_server_status/at_server_status.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:duration/duration.dart';
import 'package:meta/meta.dart';
import '../version.dart' show packageVersion;

import 'auth_cli_arg_validation.dart';

final AtSignLogger logger = AtSignLogger(' CLI ');

final aca = AuthCliArgs();

Directory? storageDir;

void _showPreOnboardingKeyWarning() {
  stdout.writeln();
  stdout.writeln(chalk.yellow('⚠️  IMPORTANT - READ CAREFULLY ⚠️'));
  stdout.writeln();
  stdout.writeln(chalk.bold(
      'You are about to onboard your atSign and generate a set of unique cryptographic keys.'));
  stdout.writeln(chalk.bold(
      'It is CRITICAL that you back up these keys to more than one place after onboarding.'));
  stdout.writeln();
  stdout.writeln(chalk.red('LOSING ACCESS TO THESE KEYS WILL RESULT IN:'));
  stdout.writeln(
      '• Loss of ability to authenticate into your atSign\'s atServer');
  stdout.writeln(
      '• Loss of ability to decrypt any data on your atSign\'s atServer');
  stdout.writeln(
      '• Loss of data access to any applications/devices that use these keys');
  stdout.writeln();
  stdout.writeln(chalk.bold(
      'If you lose these keys, you will NOT be able to recover your atSign or its data.'));
  stdout.writeln(
      chalk.bold('NOT EVEN ATSIGN INC. CAN RECOVER THESE KEYS FOR YOU!'));
  stdout.writeln(chalk.bold(
      'You may reset your atSign\'s atServer by contacting support@atsign.com, if a new set of keys is required, but no data can be recovered.'));
  stdout.writeln();
  stdout.writeln(chalk.blue('IMPORTANT:'));
  stdout.writeln(
      '• After onboarding, you MUST back up your .atKeys file to a secure location');
  stdout.writeln(
      '• Store it in multiple secure locations (cloud storage, external drives, etc.)');
  stdout.writeln('• Keep it safe from unauthorized access');
  stdout.writeln();

  while (true) {
    stdout.write(chalk.blue('[Action Required] ') +
        chalk.bold(
            'Do you understand that losing these keys means losing access to your atSign and all its data? (Y/N): '));
    String? response = stdin.readLineSync();

    if (response != null) {
      String normalized = response.trim().toLowerCase();
      if (normalized == 'y' || normalized == 'yes') {
        stdout.writeln();
        stdout.writeln(chalk.green(
            '✓ Acknowledged. Please remember to back up your keys securely!'));
        stdout.writeln();
        break;
      } else if (normalized == 'n' || normalized == 'no') {
        stdout.writeln();
        stdout.writeln(chalk.red(
            'Onboarding cancelled. Please ensure you understand the importance of key backup before proceeding.'));
        exit(0);
      } else {
        stdout.writeln(chalk.yellow('Please enter Y (yes) or N (no).'));
        continue;
      }
    }
  }
}

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
  // NOTE: a retrofit reads a keyfile and writes back what it decided from what
  // it read, so two CLIs on one keyfile can each write a different enrollment
  // into it. This serialises the whole sequence on a lock beside the keyfile.
  retrofitSerializer = fileRetrofitSerializer;
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
    stderr.writeln('Version: $packageVersion');
    stderr.writeln('You must supply a command.');
    aca.parser.printAllCommandsUsage(showSubCommandParams: false);
    stderr.writeln('\n'
        'Use --help or -h flag to show full usage of all commands'
        '\n');
    return 1;
  }

  final first = arguments.first;
  if (first.startsWith('-') &&
      first != '-h' &&
      first != '--help' &&
      first != '--version') {
    stderr.writeln('Version: $packageVersion');
    stderr.writeln('No command was given. "$first" is an option, not a '
        'command — an invocation with no command used to be treated as '
        '"onboard", and no longer is. Name the command you want:');
    aca.parser.printAllCommandsUsage(showSubCommandParams: false);
    stderr.writeln('\nFor an activation that is "onboard": '
        'auth onboard -a <atSign> -c <cram secret>\n');
    return 1;
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
    stderr.writeln('Version: $packageVersion');
    aca.sharedArgsParser
        .printAllCommandsUsage(header: 'Arguments common to all commands: ');
    aca.parser.printAllCommandsUsage(showSubCommandParams: true);
    stderr.writeln();
    return 0;
  }

  if (topLevelResults.wasParsed(AuthCliArgs.argNameVersion)) {
    stdout.writeln('Version: $packageVersion');
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
        stderr.writeln('Version: $packageVersion');
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
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.otp:
        // generate a one-time-passcode for this atSign. This is a passcode
        // which enrolling apps can provide which will signal that this is a
        // real enrollment request and will be accepted by the atServer.
        // Note that enrollment requests always require approval from an
        // already-authenticated authorized atClient - the passcode on
        // enrollment requests is used solely to defend against ddos attacks
        // where users are bombarded with spurious enrollment requests.
        await outputOtp(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.interactive:
        // Interactive session for various enrollment management activities:
        // - listing, approving, denying and revoking enrollments
        // - setting spp, generating otp, etc
        await interactive(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.list:
        await list(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.fetch:
        await fetch(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.approve:
        await approve(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.auto:
        await autoApprove(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.deny:
        await deny(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.revoke:
        await revoke(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

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
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));

      case AuthCliCommand.delete:
        await deleteEnrollment(
            commandArgResults,
            await createAtClient(
                atSign: commandArgResults[AuthCliArgs.argNameAtSign],
                atKeysFilePath: commandArgResults[AuthCliArgs.argNameAtKeys],
                rootDomain: commandArgResults[AuthCliArgs.argNameRootServer],
                passPhrase: commandArgResults[AuthCliArgs.argNamePassPhrase],
                waitForPqStartup: false,
                posture: AuthCliArgs.postureForApprover(commandArgResults)));
      case AuthCliCommand.decrypt:
        await passPhraseDecryptAtKeys(commandArgResults);

      case AuthCliCommand.version:
        stdout.writeln('Version: $packageVersion');
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

  // rootServer is now an alias of root-server, ArgParser handles both automatically
  String rootServer = ar[AuthCliArgs.argNameRootServer];

  // Parse rootServer using AtRootDomain
  AtRootDomain rootDomain;
  try {
    rootDomain = AtRootDomain.parse(rootServer);
  } catch (e) {
    stderr.writeln('Error: Invalid root server domain "$rootServer": $e');
    exit(1);
  }

  SecondaryAddressFinder saf = CacheableSecondaryAddressFinder(
      rootDomain.rootDomain, rootDomain.rootPort);
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
    // NOTE: a public key lookup needs no authentication, and no credential is
    // held here.
    final AtLookUp al = AtLookUp.withSecureSocket(
      atSign: atSign,
      rootDomain: rootDomain,
      transport: secureSocketTransport(SecureSocketConfig()),
      authenticator: null,
    );
    try {
      pk = await al.executeCommand('lookup:publickey$atSign\n', auth: false);
    } on AtLookUpException catch (e) {
      final e1 = AtExceptionUtils.get(e.errorCode, e.errorMessage);
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

/// How often a client waiting for its enrollment to be approved asks again,
/// and how many times an activation asks whether a newly registered atSign
/// has been provisioned.
const Duration approvalPollInterval = Duration(seconds: 10);
const Duration provisioningPollInterval = Duration(seconds: 2);

/// Activates the atSign the arguments name, writing its first keys to the
/// keyfile they name. With no `--cramkey`, the registrar sends a
/// verification code to the atSign's email and hands the CRAM secret over
/// against it.
///
/// [atLookUp] is a connection to activate over, for a test; a run finds the
/// atServer through the atDirectory.
@visibleForTesting
Future<bool> onboard(ArgResults argResults, {AtLookUp? atLookUp}) async {
  if (argResults[AuthCliArgs.argNameVersion]) {
    stdout.writeln('Version: $packageVersion');
    return false;
  }
  final preference = onboardingPreferenceFrom(argResults);
  final atSign = AtUtils.fixAtSign(argResults[AuthCliArgs.argNameAtSign]);
  logger.info('Root server is ${argResults[AuthCliArgs.argNameRootServer]}');
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
    // if  -y flag is not used and --cramkey is not provided, show back up key warning message
    // --cramkey implies --yes for backwards compatibility with automation scripts
    if (!argResults[AuthCliArgs.argNameYes] &&
        !argResults.wasParsed(AuthCliArgs.argNameCramSecret)) {
      _showPreOnboardingKeyWarning();
    }
    await activate(atSign, preference,
        maxRetries: int.parse(argResults[AuthCliArgs.argNameMaxRetries]),
        atLookUp: atLookUp);
    return true;
  } catch (e) {
    await Future.delayed(Duration(milliseconds: 10));
    throw ('Onboarding failed : $e');
  }
}

/// CRAM-activates [atSign] and writes its first keys to the keyfile
/// [preference] names, fetching the CRAM secret from the registrar when the
/// preference carries none. An atSign that is already activated is refused
/// before anything is minted. The client the activation opens is stopped
/// before this returns: a command's process ends with the command.
///
/// [maxRetries] bounds the wait for a newly registered atSign to be
/// provisioned, [provisioningPollInterval] apart.
@visibleForTesting
Future<void> activate(String atSign, AtOnboardingPreference preference,
    {int maxRetries = 50, AtLookUp? atLookUp}) async {
  final atKeysFilePath = preference.atKeysFilePath!;
  AtFileUtil.ensureWritable(File(atKeysFilePath));
  preference.cramSecret ??= await _cramSecretFromRegistrar(atSign, preference);
  final connection =
      atLookUp ?? await _proxyLookUp(atSign, preference, context: 'onboard');
  if (await _isActivated(atSign, preference, connection)) {
    throw AtActivateException('atsign $atSign is already activated');
  }

  final client = await Atsign(atSign).activate(
      cramSecret: preference.cramSecret!,
      keys: FileAtKeysIo(
          filePath: (_) => atKeysFilePath, passPhrase: preference.passPhrase),
      preference: preference,
      storage: preference.storageFor(atSign),
      provisioningRetries: maxRetries,
      provisioningPollInterval: provisioningPollInterval,
      onProgress: printProgress,
      atLookUp: connection);
  stdout.writeln('[Success] Your keyfile stored at path: $atKeysFilePath');
  await AtFileUtil.setSecureFilePermissions(atKeysFilePath);
  if (preference.passPhrase != null) {
    stdout.writeln(
        '${chalk.blue('[Information]')} Encrypted atKeys file with the given pass phrase');
  }
  await client.stop();
}

/// The CRAM secret for [atSign] from the registrar: it emails a verification
/// code to the atSign's owner, who types it in here.
Future<String> _cramSecretFromRegistrar(
    String atSign, AtOnboardingPreference preference) async {
  final util = OnboardingUtil();
  await util.requestAuthenticationOtp(atSign,
      authority: preference.registrarUrl);
  final otp = util.getVerificationCodeFromUser();
  return util.getCramKey(atSign, otp, authority: preference.registrarUrl);
}

/// Whether [atSign]'s atServer already holds an encryption public key, which
/// an activation publishes and nothing else does. Asked through
/// [connection] when there is one, since a proxied atServer is not the
/// atDirectory's to report on; otherwise the atDirectory's status is read.
Future<bool> _isActivated(String atSign, AtOnboardingPreference preference,
    AtLookUp? connection) async {
  if (connection != null) {
    try {
      final response = await connection
          .executeCommand('lookup:publickey$atSign\n', auth: false);
      return response != null &&
          response.startsWith('data:') &&
          !response.contains('null') &&
          response.trim().length > 'data:'.length;
    } catch (e) {
      logger.info('lookup:publickey$atSign failed, so $atSign is taken as '
          'not activated: $e');
      return false;
    }
  }
  try {
    final status = await AtStatusImpl(
            rootUrl: preference.rootDomain, rootPort: preference.rootPort)
        .get(atSign);
    return status.status() == AtSignStatus.activated;
  } catch (e) {
    stderr.writeln('${chalk.brightRed('[Error]')} $e');
    throw AtActivateException(
        'Could not determine atsign activation status: $e',
        intent: Intent.fetchData);
  }
}

/// A connection to a proxied atServer, with the `from:` that tells the proxy
/// which atSign the connection is for already sent; null when [preference]
/// names no proxy, since the atDirectory then finds the atServer.
Future<AtLookUp?> _proxyLookUp(String atSign, AtOnboardingPreference preference,
    {required String context}) async {
  if (!preference.isUsingProxy) return null;
  final lookUp = AtLookUp.withSecureSocket(
    atSign: atSign,
    rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
    transport: secureSocketTransport(SecureSocketConfig()),
    authenticator: null,
  );
  try {
    final response =
        await lookUp.executeCommand('from:$atSign\n', auth: false);
    logger.info('$context: from: for $atSign answered $response');
  } catch (e) {
    logger.warning('$context: from: for $atSign failed: $e - continuing');
  }
  return lookUp;
}

/// auth enroll : require atSign, app name, device name, otp, atKeys path
///     If atKeys file doesn't exist, then this is a new enrollment
///     If it holds a request submitted earlier for this app and device, the
///         wait for approval resumes from it
///
/// [atLookUp] is a connection to enrol over, for a test.
@visibleForTesting
Future<bool> enroll(ArgResults argResults, {AtLookUp? atLookUp}) async {
  if (!argResults.wasParsed(AuthCliArgs.argNameAtKeys)) {
    throw ArgumentError('The --${AuthCliArgs.argNameAtKeys} option is'
        ' mandatory for the "enroll" command');
  }
  final preference = onboardingPreferenceFrom(argResults);
  final atSign = AtUtils.fixAtSign(argResults[AuthCliArgs.argNameAtSign]);

  Map<String, String> namespaces = {};
  String nsArg = argResults[AuthCliArgs.argNameNamespaceAccessList];
  List<String> nsList = nsArg.split(',');
  for (String item in nsList) {
    List<String> l = item.split(':');
    String namespace = l[0].replaceAll('"', '').trim();
    String permission = l[1].replaceAll('"', '').trim();
    namespaces[namespace] = permission;
  }

  // If apkam Keys expiry is not set, then APKAM keys should live forever.
  // Therefore set to 0ms (0 milliseconds) and TTL will not be set.
  String apkamKeysExpiry = argResults[AuthCliArgs.argNameExpiry] ?? '0ms';

  final client = await enrolDevice(
    atSign: atSign,
    preference: preference,
    app: argResults[AuthCliArgs.argNameAppName],
    device: argResults[AuthCliArgs.argNameDeviceName],
    otp: argResults[AuthCliArgs.argNamePasscode],
    namespaces: namespaces,
    atKeysFilePath: argResults[AuthCliArgs.argNameAtKeys],
    apkamKeysExpiry: parseDuration(apkamKeysExpiry),
    maxRetries: int.parse(argResults[AuthCliArgs.argNameMaxRetries]),
    // NOTE: the minted key's algorithm has to agree with the posture the
    // enrolment is submitted under, or at_chops is handed a key of one
    // algorithm and a declaration of another.
    signingAlgo: AuthCliArgs.postureForEnroller(argResults)
        .posture
        .authenticationKeyAlgorithm,
    // NOTE: null means the posture decides. This is asked separately from the
    // posture because a pq request carries no wrapped key, so an approver that
    // cannot convey approves an enrollment that can decrypt nothing, and only
    // the caller knows which approver will pick the request up.
    keyExchangeMode: AuthCliArgs.keyExchangeIn(argResults),
    atLookUp: atLookUp,
  );
  await client.stop();
  return true;
}

/// Enrols this device as [app] on [device], waits for the approval, and
/// opens a client on the keys it completes, which the caller stops.
///
/// The keyfile at [atKeysFilePath] is the resume record: a request submitted
/// earlier for the same app and device is waited on again rather than
/// repeated, and a keyfile already holding live keys is refused.
@visibleForTesting
Future<AtClient> enrolDevice({
  required String atSign,
  required AtOnboardingPreference preference,
  required String app,
  required String device,
  required String otp,
  required Map<String, String> namespaces,
  required String atKeysFilePath,
  required SigningAlgoType signingAlgo,
  EnrollmentKeyExchangeMode? keyExchangeMode,
  Duration? apkamKeysExpiry,
  int maxRetries = 5,
  Duration retryInterval = approvalPollInterval,
  AtLookUp? atLookUp,
}) async {
  final keys = FileAtKeysIo(
      filePath: (_) => atKeysFilePath, passPhrase: preference.passPhrase);
  final connection =
      atLookUp ?? await _proxyLookUp(atSign, preference, context: 'enroll');
  var pending = await Atsign(atSign).resumeEnrollment(
      app: app,
      device: device,
      keys: keys,
      preference: preference,
      atLookUp: connection);
  if (pending != null) {
    stderr.writeln('${chalk.blue('[Information]')} Resuming enrollment '
        '${pending.enrollmentId}, submitted earlier from this keyfile');
  } else {
    pending = await Atsign(atSign).enroll(
        otp: otp,
        app: app,
        device: device,
        namespaces: namespaces,
        keys: keys,
        preference: preference,
        signingAlgo: signingAlgo,
        keyExchangeMode: keyExchangeMode,
        apkamKeysExpiry: apkamKeysExpiry,
        atLookUp: connection);
  }
  stdout.writeln('Enrollment ID: ${pending.enrollmentId}');
  final narration = pending.progress.listen(printProgress);
  try {
    final client = await pending.client(preference,
        storage: preference.storageFor(atSign),
        retryInterval: retryInterval,
        maxRetries: maxRetries);
    await AtFileUtil.setSecureFilePermissions(atKeysFilePath);
    stdout.writeln(
        '${chalk.green('[Success]')} Your .atKeys file saved at $atKeysFilePath\n');
    return client;
  } finally {
    await narration.cancel();
  }
}

@visibleForTesting
Future<void> setSpp(ArgResults argResults, AtClient atClient) async {
  String spp = argResults[AuthCliArgs.argNameSpp];
  String? sppExpiry = argResults[AuthCliArgs.argNameExpiry];
  if (invalidSpp(spp)) {
    throw ArgumentError(invalidSppMsg);
  }

  final passcode = await atClient.enrollments.spp(spp,
      expiry: sppExpiry == null || sppExpiry.isEmpty
          ? null
          : parseDuration(sppExpiry));
  stdout.writeln('SPP set: ${passcode.value}'
      '${passcode.expiry == null ? '' : ', valid until ${passcode.expiry}'}');
}

@visibleForTesting
Future<void> outputOtp(ArgResults argResults, AtClient atClient) async {
  String? otpExpiry = argResults[AuthCliArgs.argNameExpiry];
  try {
    String otp = await requestEnrollmentOtp(atClient, otpExpiry: otpExpiry);
    stdout.writeln(otp);
  } catch (e) {
    stderr.writeln(e);
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
        case AuthCliCommand.decrypt:
          stderr.writeln('The "${cliCommand.name}" command'
              ' may not be used in interactive session');

        case AuthCliCommand.spp:
          await setSpp(commandArgResults, atClient);

        case AuthCliCommand.otp:
          await outputOtp(commandArgResults, atClient);

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

        case AuthCliCommand.version:
          stdout.writeln('Version: $packageVersion');
      }
    } on ArgumentError catch (e) {
      stderr.writeln(
          'Argument error for command ${cliCommand.name}: ${e.message}');
      commandParser.printAllCommandsUsage(header: 'Usage: ${cliCommand.name}');
    }
  }
}

/// The roster narrowed to [status] when given, then to the app and device
/// name patterns.
Future<List<Enrollment>> _list(
  String? status,
  AtClient atClient, {
  String? arx,
  String? drx,
}) async {
  final ar = arx == null ? null : RegExp(arx);
  final dr = drx == null ? null : RegExp(drx);
  final all = await atClient.enrollments.list(
      statuses: status == null ? null : [EnrollmentStatus.values.byName(status)]);
  final filtered = all
      .where((e) => ar == null || ar.hasMatch(e.appName ?? ''))
      .where((e) => dr == null || dr.hasMatch(e.deviceName ?? ''))
      .toList();
  stdout.writeln("Found ${filtered.length} matching enrollment records");
  return filtered;
}

Future<void> list(ArgResults ar, AtClient atClient) async {
  String? statusFilter = ar[AuthCliArgs.argNameEnrollmentStatus];
  String? arx = ar[AuthCliArgs.argNameAppNameRegex];
  String? drx = ar[AuthCliArgs.argNameDeviceNameRegex];

  final records = await _list(statusFilter, atClient, arx: arx, drx: drx);
  stdout.write('Enrollment ID'.padRight(38));
  stdout.write('Status'.padRight(10));
  stdout.write('AppName'.padRight(20));
  stdout.write('DeviceName'.padRight(38));
  stdout.writeln('Namespaces');
  for (final e in records) {
    stdout.writeln('${(e.enrollmentId ?? '').padRight(38)}'
        '${(e.status ?? '').padRight(10)}'
        '${(e.appName ?? '').padRight(20)}'
        '${(e.deviceName ?? '').padRight(38)}'
        '${e.namespace}');
  }
}

Future<void> fetch(ArgResults argResults, AtClient atClient) async {
  String eId = argResults[AuthCliArgs.argNameEnrollmentId];
  final record = await atClient.enrollments.fetch(eId);
  if (record == null) {
    stderr.writeln('Enrollment ID $eId not found');
  } else {
    stdout.writeln('Fetched enrollment OK: ${jsonEncode(record.toJson())}');
  }
}

/// The enrollments a decision applies to: the one [eId] names, else those
/// in [status] whose app and device names match the patterns. One of the
/// three must be given.
Future<List<Enrollment>> _fetchOrListAndFilter(
  AtClient atClient,
  String status, {
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
  if (eId != null) {
    final record = await atClient.enrollments.fetch(eId);
    if (record == null) {
      stderr.writeln('Enrollment ID $eId not found');
      return const [];
    }
    return [record];
  }
  return _list(status, atClient, arx: arx, drx: drx);
}

Future<int> approve(ArgResults ar, AtClient atClient, {int? limit}) async {
  int approved = 0;
  final toApprove = await _fetchOrListAndFilter(
    atClient,
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
  for (final er in toApprove) {
    final eId = er.enrollmentId!;
    stdout.writeln('Approving enrollmentId $eId'
        ' with appName "${er.appName}"'
        ' and deviceName "${er.deviceName}"');
    // NOTE: approving is also when this atSign's secrets are sealed to the new
    // device's key package, which is why it goes through the client.
    await atClient.enrollments.approve(eId);
    stdout.writeln('Approved $eId');

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

      // NOTE: approving is also when this atSign's secrets are sealed to the
      // new device's key package, which is why it goes through the client.
      await atClient.enrollments.approve(eId);
      stdout.writeln('Approval successful.');

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
  final toDeny = await _fetchOrListAndFilter(
    atClient,
    EnrollmentStatus.pending.name, // must be status pending
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toDeny.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  for (final er in toDeny) {
    final eId = er.enrollmentId!;
    stdout.writeln('Denying enrollmentId $eId');
    await atClient.enrollments.deny(eId);
    stdout.writeln('Denied $eId');
  }
}

Future<void> revoke(ArgResults ar, AtClient atClient) async {
  final toRevoke = await _fetchOrListAndFilter(
    atClient,
    EnrollmentStatus.approved.name, // must be status approved
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toRevoke.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  for (final er in toRevoke) {
    final eId = er.enrollmentId!;
    stdout.writeln('Revoking enrollmentId $eId');
    await atClient.enrollments.revoke(eId);
    stdout.writeln('Revoked $eId');
  }
}

Future<void> unrevoke(ArgResults ar, AtClient atClient) async {
  final toUnRevoke = await _fetchOrListAndFilter(
    atClient,
    EnrollmentStatus.revoked.name, // must be status revoked
    eId: ar[AuthCliArgs.argNameEnrollmentId],
    arx: ar[AuthCliArgs.argNameAppNameRegex],
    drx: ar[AuthCliArgs.argNameDeviceNameRegex],
  );

  if (toUnRevoke.isEmpty) {
    stderr.writeln('No matching enrollment(s) found');
    return;
  }

  for (final er in toUnRevoke) {
    final eId = er.enrollmentId!;
    stdout.writeln('Un-Revoking enrollmentId $eId');
    await atClient.enrollments.unrevoke(eId);
    stdout.writeln('Un-Revoked $eId');
  }
}

Future<void> deleteEnrollment(ArgResults ar, AtClient atClient) async {
  String eId = ar[AuthCliArgs.argNameEnrollmentId];
  stdout.writeln('Sending delete request');
  await atClient.enrollments.delete(eId);
  stdout.writeln('Deleted $eId');
}

Future<void> passPhraseDecryptAtKeys(ArgResults ar) async {
  final atSign = (ar[AuthCliArgs.argNameAtSign] as String).toAtsign();
  final passPhrase = ar[AuthCliArgs.argNamePassPhrase];

  if (passPhrase == null || passPhrase.isEmpty) {
    throw ArgumentError(
        'The --${AuthCliArgs.argNamePassPhrase} option is mandatory for the "decrypt" command');
  }

  final atKeysFilePath =
      ar[AuthCliArgs.argNameAtKeys] ?? HomeDirectoryUtil.getAtKeysPath(atSign);
  if (atKeysFilePath.isEmpty) {
    throw ArgumentError(
        'The --${AuthCliArgs.argNameAtKeys} option must not be empty');
  }
  if (!File(atKeysFilePath).existsSync()) {
    throw ArgumentError('Keys file does not exist at $atKeysFilePath');
  }

  String targetKeyFilePath = ar[AuthCliArgs.argNameTargetAtKeys];
  if (!targetKeyFilePath.endsWith('.atKeys')) {
    targetKeyFilePath = '$targetKeyFilePath.atKeys';
  }

  stderr.writeln('Decrypting atKeys file with passphrase...');
  final reader =
      FileAtKeysIo(filePath: (_) => atKeysFilePath, passPhrase: passPhrase);
  final decryptedAtKeys = await reader.read(atSign);

  final writer = FileAtKeysIo(filePath: (_) => targetKeyFilePath);
  await writer.write(atSign, decryptedAtKeys);
  stdout.writeln(
      '${chalk.green('[Success]')} Decrypted atKeys file stored at $targetKeyFilePath');
}

/// The preference the arguments describe, under the posture an enroller
/// command runs at; the posture is final on a preference, so it is fixed at
/// construction.
@visibleForTesting
AtOnboardingPreference onboardingPreferenceFrom(ArgResults ar) {
  final atSign = AtUtils.fixAtSign(ar[AuthCliArgs.argNameAtSign]);

  // rootServer is now an alias of root-server, ArgParser handles both automatically
  String rootServer = ar[AuthCliArgs.argNameRootServer];

  // Parse rootServer using AtRootDomain
  AtRootDomain rootDomain;
  try {
    rootDomain = AtRootDomain.parse(rootServer);
  } catch (e) {
    stderr.writeln('Error: Invalid root server domain "$rootServer": $e');
    throw ArgumentError('Invalid root server domain: $e');
  }

  final enroller = AuthCliArgs.postureForEnroller(ar);
  if (enroller.notice != null) {
    stderr.writeln('${chalk.blue('[Information]')} ${enroller.notice}');
  }
  return AuthCliArgs.preferenceUnder(enroller.posture)
    ..rootDomain = rootDomain.rootDomain
    ..rootPort = rootDomain.rootPort
    ..registrarUrl = ar[AuthCliArgs.argNameRegistrarFqdn]
    ..cramSecret = ar[AuthCliArgs.argNameCramSecret]
    ..atKeysFilePath =
        ar[AuthCliArgs.argNameAtKeys] ?? HomeDirectoryUtil.getAtKeysPath(atSign)
    ..passPhrase = ar[AuthCliArgs.argNamePassPhrase]
    ..storagePath = HomeDirectoryUtil.getHiveStoragePath(atSign)
    ..hashingAlgoType =
        HashingAlgoType.fromString(ar[AuthCliArgs.argNameHashingAlgoType]);
}

String _lastProgressGroup = '';
int _progressPad = 10;

/// Narrates one step of an activation or an enrollment on stderr, the group
/// padded so the steps line up.
void printProgress(ProgressEvent pe) {
  if (pe.group.isNotEmpty && pe.group != _lastProgressGroup) {
    stderr.writeln();
  }
  if (pe.group.length > _progressPad) {
    _progressPad = pe.group.length;
  }
  _lastProgressGroup = pe.group;
  String output = '${pe.type.chalkFn(pe.group.padLeft(_progressPad))} : ${pe.msg}'
      .replaceAll('\n', '\\n')
      .replaceAll('\t', ' ');
  int viewableLength = '${pe.group.padLeft(_progressPad)} : ${pe.msg}'
      .replaceAll('\n', '\\n')
      .replaceAll('\t', ' ')
      .length;
  int diff = output.length - viewableLength;
  if (stdout.hasTerminal && viewableLength > (stdout.terminalColumns - 3)) {
    output = '${output.substring(0, stdout.terminalColumns - 3 + diff)}...';
  }
  stderr.writeln('\r\x1b[K$output');
}
