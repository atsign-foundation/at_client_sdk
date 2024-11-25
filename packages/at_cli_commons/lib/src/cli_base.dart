import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/src/service_factories.dart';
import 'package:at_cli_commons/src/utils.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';
import 'package:version/version.dart';

class CLIBase {
  static const defaultMaxConnectAttempts = 20;

  /// An ArgParser which has all of the options and flags required by [CLIBase]
  /// Used by [fromCommandLineArgs] if the `parser` parameter isn't supplied.
  static final ArgParser argsParser = ArgParser()
    ..addFlag('help', negatable: false, help: 'Usage instructions')
    ..addOption('atsign',
        abbr: 'a', mandatory: true, help: 'This client\'s atSign')
    ..addOption('namespace', abbr: 'n', mandatory: true, help: 'Namespace')
    ..addOption('key-file',
        abbr: 'k',
        mandatory: false,
        help: 'Your atSign\'s atKeys file if not in ~/.atsign/keys/')
    ..addOption('cram-secret',
        abbr: 'c', mandatory: false, help: 'atSign\'s cram secret')
    ..addOption('home-dir', abbr: 'h', mandatory: false, help: 'home directory')
    ..addOption('storage-dir',
        abbr: 's',
        mandatory: false,
        help: 'directory for this client\'s local storage files')
    ..addOption('root-domain',
        abbr: 'd',
        mandatory: false,
        help: 'Root Domain',
        defaultsTo: 'root.atsign.org')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'More logging')
    ..addFlag('never-sync', negatable: false, help: 'Do not run sync')
    ..addOption('max-connect-attempts',
        help: 'Number of times to attempt to initially connect to atServer.'
            ' Note: there is a 3-second delay between connection attempts.',
        defaultsTo: defaultMaxConnectAttempts.toString());

  /// Constructs a CLIBase from a list of command-line arguments
  /// and calls [init] on it.
  /// <br/>
  /// <br/>
  /// If [parser] is not supplied then uses CLIBase's [argsParser] static var.
  /// Allowing [parser] to be supplied enables callers to do something like this:
  /// ```
  ///     ArgParser argsParser = CLIBase.argsParser
  ///       ..addOption('my-cli-option',
  ///          help: "an option which configures my cli's unique feature");
  ///
  ///     CLIBase cliBase = await CLIBase.fromCommandLineArgs(args, parser: argsParser);
  /// ```
  static Future<CLIBase> fromCommandLineArgs(List<String> args,
      {ArgParser? parser}) async {
    parser ??= argsParser;
    ArgResults parsedArgs = parser.parse(args);

    if (parsedArgs['help'] == true) {
      print(parser.usage);
      exit(0);
    }

    CLIBase cliBase = CLIBase(
      atSign: parsedArgs['atsign'],
      atKeysFilePath: parsedArgs['key-file'],
      nameSpace: parsedArgs['namespace'],
      rootDomain: parsedArgs['root-domain'],
      homeDir: getHomeDirectory(),
      storageDir: parsedArgs['storage-dir'],
      verbose: parsedArgs['verbose'],
      cramSecret: parsedArgs['cram-secret'],
      syncDisabled: parsedArgs['never-sync'],
      maxConnectAttempts: int.parse(parsedArgs['max-connect-attempts']),
    );

    await cliBase.init();

    return cliBase;
  }

  late final String atSign;
  final String nameSpace;
  final String rootDomain;
  final String? homeDir;
  final String? atKeysFilePath;
  final String? storageDir;
  final String? downloadDir;
  final String? cramSecret;
  final bool syncDisabled;
  final int maxConnectAttempts;

  late final String atKeysFilePathToUse;
  late final String localStoragePathToUse;
  late final String downloadPathToUse;

  final bool verbose;

  late final AtSignLogger logger;
  late final AtClient atClient;

  /// Validates parameters and constructs a CLIBase instance.
  /// <br/> <br/>
  /// Validation rules:
  /// - homeDir must be non-null when any of the atKeysFilePath, storageDir or
  ///   downloadDir parameters are null
  ///
  /// <br/>
  /// Also configures the default AtSignLogger log level to be either INFO
  /// if verbose is true, or SHOUT if verbose is false (the default). If the
  /// application wishes to use a different default log level then it can do
  /// something like this:
  /// ```
  ///     AtSignLogger.root_level = 'FINEST';
  ///     cliBase.logger.logger.level = Level.FINEST;
  /// ```
  /// Throws an [IllegalArgumentException] if the parameters fail validation.
  CLIBase({
    required String atSign,
    required this.nameSpace,
    required this.rootDomain,
    this.homeDir,
    this.verbose = false,
    this.atKeysFilePath,
    this.storageDir,
    this.downloadDir,
    this.cramSecret,
    this.syncDisabled = false,
    this.maxConnectAttempts = defaultMaxConnectAttempts,
  }) {
    this.atSign = AtUtils.fixAtSign(atSign);
    if (homeDir == null) {
      if (atKeysFilePath == null) {
        throw IllegalArgumentException(
            'homeDir must be provided when atKeysFilePath is not provided');
      }
      if (storageDir == null) {
        throw IllegalArgumentException(
            'homeDir must be provided when storageDir is not provided');
      }
      if (downloadDir == null) {
        throw IllegalArgumentException(
            'homeDir must be provided when downloadDir is not provided');
      }
    }

    atKeysFilePathToUse =
        (atKeysFilePath ?? '$homeDir/.atsign/keys/${this.atSign}_key.atKeys')
            .replaceAll('/', Platform.pathSeparator);
    localStoragePathToUse = (storageDir ??
            standardAtClientStoragePath(
              baseDir: homeDir!,
              atSign: this.atSign,
              progName: nameSpace,
              uniqueID: 'single',
            ))
        .replaceAll('/', Platform.pathSeparator);
    downloadPathToUse =
        (downloadDir ?? '$homeDir!/.atsign/downloads/${this.atSign}/$nameSpace')
            .replaceAll('/', Platform.pathSeparator);

    AtSignLogger.defaultLoggingHandler = AtSignLogger.stdErrLoggingHandler;

    logger = AtSignLogger(runtimeType.toString());
    logger.hierarchicalLoggingEnabled = true;
    if (verbose) {
      AtSignLogger.root_level = 'INFO';
      logger.logger.level = Level.INFO;
    } else {
      AtSignLogger.root_level = 'SHOUT';
      logger.logger.level = Level.SHOUT;
    }
  }

  /// Does the various things required to create an AtClient object
  Future<void> init() async {
    AtServiceFactory? atServiceFactory;

    if (syncDisabled) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }

    AtOnboardingPreference atOnboardingConfig = AtOnboardingPreference()
      ..hiveStoragePath = localStoragePathToUse
      ..namespace = nameSpace
      ..downloadPath = downloadPathToUse
      ..isLocalStoreRequired = true
      ..commitLogPath = '$localStoragePathToUse/commitLog'
          .replaceAll('/', Platform.pathSeparator)
      ..rootDomain = rootDomain
      ..fetchOfflineNotifications = true
      ..atKeysFilePath = atKeysFilePathToUse
      ..cramSecret = cramSecret
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
        atSign, atOnboardingConfig,
        atServiceFactory: atServiceFactory);

    if (!File(atKeysFilePathToUse).existsSync()) {
      await onboardingService.onboard();
    }

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
        authenticated = await onboardingService.authenticate();
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
      throw SecondaryServerConnectivityException(msg);
    }
    stderr.writeln(chalk.brightGreen('Connected'));

    // Get the AtClient which the onboardingService just authenticated
    atClient = AtClientManager.getInstance().atClient;
  }
}
