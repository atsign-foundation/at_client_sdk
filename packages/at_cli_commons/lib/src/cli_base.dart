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

  /// Resolves root server arguments with backward compatibility support.
  /// Prioritizes the new argument over the deprecated one and provides appropriate warnings.
  ///
  /// [args] - The parsed command line arguments
  /// [newArgName] - Name of the new argument (e.g., 'root-server')
  /// [oldArgName] - Name of the deprecated argument (e.g., 'root-domain')
  /// [defaultValue] - Default value to use if neither argument is provided
  ///
  /// Returns the resolved root server value with proper error handling
  static String resolveRootServer(
    ArgResults args, {
    required String newArgName,
    required String oldArgName,
    String defaultValue = 'root.atsign.org',
  }) {
    bool newArgProvided = args.wasParsed(newArgName);
    bool oldArgProvided = args.wasParsed(oldArgName);
    
    String finalRootServer;
    if (newArgProvided) {
      // User explicitly provided new argument
      finalRootServer = args[newArgName];
      if (oldArgProvided) {
        // Both explicitly provided, warn user
        print('Warning: Both --$oldArgName and --$newArgName provided. Using --$newArgName value: $finalRootServer');
        print('Note: --$oldArgName is deprecated, please use --$newArgName instead.');
      }
    } else if (oldArgProvided) {
      // User explicitly provided deprecated argument
      finalRootServer = args[oldArgName];
      print('Warning: --$oldArgName is deprecated, please use --$newArgName instead.');
    } else {
      // Neither provided explicitly, use default
      finalRootServer = defaultValue;
    }

    // Parse and validate the root domain
    try {
      AtRootDomain parsedRootDomain = AtRootDomain.parse(finalRootServer);
      return parsedRootDomain.rootDomain;
    } catch (e) {
      print('Error: Invalid root server domain "$finalRootServer": $e');
      exit(1);
    }
  }

  static const Set<String> hideableArgs = {
    'key-file',
    'home-dir',
    'storage-dir',
    'root-domain', // deprecated, kept for backward compatibility
    'never-sync',
    'max-connect-attempts',
    'pass-phrase',
  };

  /// Create an ArgParser which has all of the options and flags required by
  /// [CLIBase]
  ///
  /// If [namespace] is not supplied then the ArgParser will have a mandatory
  /// `namespace` argument.
  ///
  /// If [namespace] **is** supplied then the ArgParser will have a `namespace`
  /// argument which is optional, defaulting to [namespace], and will also be
  /// hidden.
  ///
  /// You may wish many of the arguments here to be hidden, since, while they
  /// are very helpful for dev purposes, they are not so friendly for
  /// end-users.
  ///
  /// For convenience, [hideableArgs] contains a list of arguments which you
  /// will most likely wish to hide. So, for example:
  /// ```
  /// ArgParser argsParser = CLIBase.createArgsParser(namespace: 'my_app', hide: CLIBase.hideableArgs)
  ///   ..addOption('my-cli-option', help: "something specific to my cli");
  ///
  /// CLIBase cliBase = await CLIBase.fromCommandLineArgs(args, parser: argsParser);
  /// ```
  ///
  ///
  static ArgParser createArgsParser({
    String? namespace,
    Set<String> hide = const {},
  }) {
    int? usageLineLength = stdout.hasTerminal ? stdout.terminalColumns : null;
    return ArgParser(usageLineLength: usageLineLength)
      ..addFlag('help', negatable: false, help: 'Usage instructions')
      ..addOption('atsign',
          abbr: 'a', mandatory: true, help: 'The atSign to use')
      ..addOption('namespace',
          abbr: 'n',
          mandatory: namespace == null,
          defaultsTo: namespace,
          hide: namespace != null,
          help: 'Namespace')
      ..addOption('key-file',
          abbr: 'k',
          mandatory: false,
          help: 'Your atSign\'s atKeys file if not in ~/.atsign/keys/',
          hide: hide.contains('key-file'))
      ..addOption('home-dir',
          abbr: 'h',
          mandatory: false,
          help: 'home directory',
          hide: hide.contains('home-dir'))
      ..addOption('storage-dir',
          abbr: 's',
          mandatory: false,
          help: 'directory for this client\'s local storage files',
          hide: hide.contains('storage-dir'))
      ..addOption('root-domain',
          abbr: 'd',
          mandatory: false,
          help: 'Root Domain (deprecated, use --root-server instead)',
          defaultsTo: 'root.atsign.org',
          hide: hide.contains('root-domain'))
      ..addOption('root-server',
          abbr: 'r',
          mandatory: false,
          help: 'Root server domain (e.g., root.atsign.org). Replaces deprecated --root-domain',
          defaultsTo: 'root.atsign.org',
          hide: hide.contains('root-server'))
      ..addFlag('verbose', abbr: 'v', negatable: false, help: 'More logging')
      ..addFlag('never-sync',
          negatable: false,
          help: 'Do not run sync',
          hide: hide.contains('never-sync'))
      ..addOption('max-connect-attempts',
          help: 'Number of times to attempt to initially connect to atServer.'
              ' Note: there is a 3-second delay between connection attempts.',
          defaultsTo: defaultMaxConnectAttempts.toString(),
          hide: hide.contains('max-connect-attempts'))
      ..addOption('pass-phrase',
          aliases: ['passPhrase'],
          abbr: 'P',
          help:
              'Pass Phrase to encrypt/decrypt the password protected atKeys file',
          mandatory: false,
          hide: hide.contains('pass-phrase'));
  }

  /// An ArgParser which has all of the options and flags required by [CLIBase]
  /// Used by [fromCommandLineArgs] if the `parser` parameter isn't supplied.
  ///
  ///
  /// This ArgParser by default will have a mandatory `namespace` argument.
  ///
  ///
  /// If your application has a fixed namespace, then use [createArgsParser]
  /// like this, for example:
  /// ```
  /// CLIBase.createArgsParser(namespace: 'my_app');
  /// ```
  static final ArgParser argsParser = createArgsParser();

  /// Constructs a CLIBase from a list of command-line arguments
  /// and calls [init] on it.
  ///
  /// Allowing [parser] to be supplied enables callers to do something like this:
  /// ```
  /// ArgParser argsParser = CLIBase.createArgsParser(namespace: 'my_app')
  ///   ..addOption('my-cli-option', help: "my cli option help");
  ///
  /// CLIBase cliBase = await CLIBase.fromCommandLineArgs(args, parser: argsParser);
  /// ```
  ///
  /// If [parser] is not supplied then we will call [createArgsParser] with
  /// the [namespace] and [hide] parameters
  static Future<CLIBase> fromCommandLineArgs(
    List<String> args, {
    ArgParser? parser,
    String? namespace,
    Set<String> hide = const {},
  }) async {
    parser ??= createArgsParser(namespace: namespace, hide: hide);
    ArgResults parsedArgs = parser.parse(args);

    if (parsedArgs['help'] == true) {
      print(parser.usage);
      exit(0);
    }

    // Resolve root server with backward compatibility
    String finalRootDomain = resolveRootServer(
      parsedArgs,
      newArgName: 'root-server',
      oldArgName: 'root-domain',
    );

    AtRootDomain parsedRootDomain = AtRootDomain.parse(finalRootDomain);

    CLIBase cliBase = CLIBase(
        atSign: parsedArgs['atsign'],
        atKeysFilePath: parsedArgs['key-file'],
        nameSpace: parsedArgs['namespace'],
        rootDomain: parsedRootDomain.rootDomain,
        homeDir: getHomeDirectory(),
        storageDir: parsedArgs['storage-dir'],
        verbose: parsedArgs['verbose'],
        syncDisabled: parsedArgs['never-sync'],
        maxConnectAttempts: int.parse(parsedArgs['max-connect-attempts']),
        passPhrase: parsedArgs['pass-phrase']);

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
  final String? passPhrase;
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
  CLIBase(
      {required String atSign,
      required this.nameSpace,
      required this.rootDomain,
      this.homeDir,
      this.verbose = false,
      this.atKeysFilePath,
      this.storageDir,
      this.downloadDir,
      this.syncDisabled = false,
      this.maxConnectAttempts = defaultMaxConnectAttempts,
      this.passPhrase}) {
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
      ..atProtocolEmitted = Version(2, 0, 0)
      ..passPhrase = passPhrase;

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
        atSign, atOnboardingConfig,
        atServiceFactory: atServiceFactory);

    if (!File(atKeysFilePathToUse).existsSync()) {
      // no atKeys file
      var msg = 'No atKeys file found at $atKeysFilePathToUse';
      stderr.writeln(chalk.brightRed(msg));
      stderr.writeln(''
          '    => If you do not have an atKeys file,'
          ' this package will help you get started:'
          ' https://pub.dev/packages/at_onboarding_cli');
      throw ArgumentError(msg);
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
