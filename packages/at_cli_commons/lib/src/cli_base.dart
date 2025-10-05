import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/src/service_factories.dart';
import 'package:at_cli_commons/src/utils.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';

class CLIBase {
  static const defaultMaxConnectAttempts = 20;

  static const Set<String> hideableArgs = {
    'key-file',
    'home-dir',
    'storage-dir',
    'root-domain',
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
    bool addLegacyRootDomainArg = true,
  }) {
    int? usageLineLength = stdout.hasTerminal ? stdout.terminalColumns : null;
    ArgParser p = ArgParser(usageLineLength: usageLineLength)
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
      ..addOption('root-server',
          aliases: const ['root-domain'],
          abbr: 'r',
          mandatory: false,
          help: 'Root server (e.g., root.atsign.org:64)',
          defaultsTo: 'root.atsign.org:64',
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
          aliases: const ['passPhrase'],
          abbr: 'P',
          help:
              'Pass Phrase to encrypt/decrypt the password protected atKeys file',
          mandatory: false,
          hide: hide.contains('pass-phrase'));

    p.addOption('legacy-root-domain',
        abbr: addLegacyRootDomainArg ? 'd' : null,
        mandatory: false,
        help: 'Deprecated abbreviation option for --root-server',
        hide: !addLegacyRootDomainArg);
    return p;
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
    bool addLegacyRootDomainArg = true,
  }) async {
    parser ??= createArgsParser(
      namespace: namespace,
      hide: hide,
      addLegacyRootDomainArg: addLegacyRootDomainArg,
    );
    ArgResults parsedArgs = parser.parse(args);

    if (parsedArgs['help'] == true) {
      print(parser.usage);
      exit(0);
    }

    String rootDomainString;
    // root-domain is now an alias of root-server, option abbreviation -r
    // we also keep optional support for the previous abbreviation, -d
    if (parsedArgs.wasParsed('legacy-root-domain')) {
      rootDomainString = parsedArgs['legacy-root-domain'];
    } else {
      rootDomainString = parsedArgs['root-server'];
    }
    try {
      AtRootDomain.parse(rootDomainString);
    } catch (e) {
      if (e is IllegalArgumentException) {
        throw ArgumentError(e.message);
      } else {
        rethrow;
      }
    }

    CLIBase cliBase = CLIBase(
        atSign: parsedArgs['atsign'],
        atKeysFilePath: parsedArgs['key-file'],
        nameSpace: parsedArgs['namespace'],
        rootDomain: rootDomainString,
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
  late final AtRootDomain atRootDomain;
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
  /// Throws an [ArgumentError] if the parameters fail validation.
  CLIBase(
      {required String atSign,
      required this.nameSpace,
      String? rootDomain,
      AtRootDomain? atRootDomain,
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
        throw ArgumentError(
            'homeDir must be provided when atKeysFilePath is not provided');
      }
      if (storageDir == null) {
        throw ArgumentError(
            'homeDir must be provided when storageDir is not provided');
      }
      if (downloadDir == null) {
        throw ArgumentError(
            'homeDir must be provided when downloadDir is not provided');
      }
    }

    if (atRootDomain != null) {
      this.atRootDomain = atRootDomain;
    } else if (rootDomain != null) {
      this.atRootDomain = AtRootDomain.parse(rootDomain);
    } else {
      throw ArgumentError('You must supply either rootDomain (String)'
          ' or atRootDomain (AtRootDomain)');
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
      ..rootDomain = atRootDomain.rootDomain
      ..rootPort = atRootDomain.rootPort
      ..fetchOfflineNotifications = true
      ..atKeysFilePath = atKeysFilePathToUse
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
