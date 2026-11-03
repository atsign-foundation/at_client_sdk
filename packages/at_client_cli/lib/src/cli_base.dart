import 'dart:io';

import 'package:args/args.dart';
import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart'
    show approvalPollInterval;
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

/// A command-line program's [AtClient], opened by [init] from the program's
/// arguments, with the keyfile and the local store defaulting to locations
/// under [homeDir].
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
  static ArgParser createArgsParser({
    String? namespace,
    Set<String> hide = const {},
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
  /// and calls [init] on it, which says what it throws.
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
    AtClientPreference? preference,
    AtLookUpFactory? lookUps,
    Duration approvalRetryInterval = approvalPollInterval,
  }) async {
    parser ??= createArgsParser(namespace: namespace, hide: hide);
    ArgResults parsedArgs = parser.parse(args);

    if (parsedArgs['help'] == true) {
      print(parser.usage);
      exit(0);
    }

    final String rootDomainString = parsedArgs['root-server'];
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
        passPhrase: parsedArgs['pass-phrase'],
        preference: preference,
        lookUps: lookUps,
        approvalRetryInterval: approvalRetryInterval);

    await cliBase.init();

    return cliBase;
  }

  late final String atSign;
  final String nameSpace;
  late final AtRootDomain atRootDomain;
  final String? homeDir;

  final String? atKeysFilePath;
  final String? storageDir;
  final String? passPhrase;
  final bool syncDisabled;
  final int maxConnectAttempts;

  final AtClientPreference? preference;

  /// Builds every connection the client opens; with none, TLS on TCP, or the
  /// proxy convention when the root domain names one.
  final AtLookUpFactory? lookUps;

  /// How long [init] waits between asking whether the enrollment a keyfile
  /// holds only the request for has been approved.
  final Duration approvalRetryInterval;

  /// What [init] builds the client's connections with: [lookUps], else what
  /// [lookUpsFor] picks for the root domain, so a `proxy:` root names the
  /// atSign first on each connection.
  @visibleForTesting
  AtLookUpFactory get lookUpsToUse =>
      lookUps ?? lookUpsFor(atRootDomain.rootDomain);

  late final String atKeysFilePathToUse;
  late final String localStoragePathToUse;

  final bool verbose;

  late final AtSignLogger logger;
  late final AtClient atClient;

  /// Validates parameters and constructs a CLIBase instance.
  /// <br/> <br/>
  /// Validation rules:
  /// - homeDir must be non-null when either of the atKeysFilePath or
  ///   storageDir parameters is null
  /// - either `atRootDomain` or `rootDomain` parameters must be non-null. If
  ///   `atRootDomain` is non-null then it is used, otherwise we parse
  ///   `rootDomain` to create an [AtRootDomain] and we use that.
  ///
  /// <br/>
  /// Also configures the default AtSignLogger log level to be either INFO
  /// if verbose is true, or WARNING if verbose is false (the default), so the
  /// SDK's warnings, such as a notification it dropped, reach stderr. If the
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
      this.syncDisabled = false,
      this.maxConnectAttempts = defaultMaxConnectAttempts,
      this.passPhrase,
      this.preference,
      this.lookUps,
      this.approvalRetryInterval = approvalPollInterval}) {
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
              uniqueID: CliKeys.defaultStoreId,
            ))
        .replaceAll('/', Platform.pathSeparator);

    AtSignLogger.defaultLoggingHandler = StdErrLoggingHandler();

    logger = AtSignLogger(runtimeType.toString());
    logger.hierarchicalLoggingEnabled = true;
    if (verbose) {
      AtSignLogger.root_level = 'INFO';
      logger.logger.level = Level.INFO;
    } else {
      AtSignLogger.root_level = 'WARNING';
      logger.logger.level = Level.WARNING;
    }
  }

  /// Opens [atClient] on the keyfile and store, and waits for it to come
  /// online.
  ///
  /// A keyfile holding only an enrollment request is resumed: [init] says it
  /// is waiting for that enrollment, waits for its approval as at_activate
  /// does, asking every [approvalRetryInterval], then opens on the keys the
  /// approval completes.
  ///
  /// Throws [AtNoCredentialException] at once when the keyfile holds no
  /// credential, as a denial, a cancel or an expiry leaves it,
  /// [AtCredentialRefusedException] when the atServer refuses the
  /// keys, [AtEnrollmentException] when the request is denied or expires,
  /// which removes its keys, [SecondaryNotFoundException] when the
  /// atDirectory has no atServer for the atSign, and the failure when the
  /// atServer is not reached, within [maxConnectAttempts] tries to open or
  /// at_activate's retries while waiting for approval
  /// ([SecondaryServerConnectivityException] for the first). No client is
  /// left open when it throws.
  Future<void> init() async {
    AtServiceFactory? atServiceFactory;

    if (syncDisabled) {
      atServiceFactory = ServiceFactoryWithNoOpSyncService();
    }

    final config = (preference ?? AtClientPreference())
      ..namespace = nameSpace
      ..rootDomain = atRootDomain.rootDomain
      ..rootPort = atRootDomain.rootPort
      ..fetchOfflineNotifications = true;

    if (!File(atKeysFilePathToUse).existsSync()) {
      // no atKeys file
      var msg = 'No atKeys file found at $atKeysFilePathToUse';
      stderr.writeln(chalk.brightRed(msg));
      stderr.writeln(''
          '    => If you do not have an atKeys file,'
          ' this package will help you get started:'
          ' https://pub.dev/packages/at_client_cli');
      throw ArgumentError(msg);
    }

    const retryDuration = Duration(seconds: 3);
    stderr.write(chalk.brightBlue('\r\x1b[KConnecting ... '));
    final keys = CliKeys.fileFor(atSign,
        path: atKeysFilePathToUse, passPhrase: passPhrase);
    Future<AtClient> open() async {
      try {
        return await Atsign(atSign).open(
            keys: keys,
            preference: config,
            namespace: nameSpace,
            storage: CliKeys.storageFor(atSign,
                program: nameSpace, path: localStoragePathToUse),
            lookUps: lookUpsToUse,
            secondaryAddressFinder: _atDirectory(),
            serviceFactory: atServiceFactory);
      } on AtOpenRefusedException catch (e) {
        throw _reported(_openFailure(e.state));
      } on AtNoCredentialException catch (e) {
        throw _reported(e);
      }
    }

    AtClient client;
    try {
      client = await open();
    } on AtEnrollmentPendingException catch (e) {
      await _awaitApproval(e, keys, config);
      client = await open();
    }
    // NOTE: one client, asked again until it is online or the budget is
    // spent; a refusal ends the wait at once, since waiting cannot change it.
    final state = await client.connection.awaitOnline(
        budget: retryDuration * maxConnectAttempts,
        retryInterval: retryDuration);
    if (!state.isOnline) {
      await client.stop();
      throw _reported(_openFailure(state));
    }
    stderr.writeln(chalk.brightGreen('Connected'));

    AtClientManager.getInstance().use(client);
    atClient = client;
  }

  /// Waits for the approval of the enrollment request [keys] holds, which
  /// completes its keys; [pending] is what opening them threw.
  Future<void> _awaitApproval(AtEnrollmentPendingException pending,
      WrittenAtKeysIo keys, AtClientPreference config) async {
    final PendingEnrollment? request;
    try {
      request = await Atsign(atSign).resumeEnrollment(
          keys: keys,
          preference: config,
          lookUps: lookUpsToUse,
          secondaryAddressFinder: _atDirectory());
    } on AtException catch (e) {
      throw _reported(e);
    }
    if (request == null) throw _reported(pending);
    stderr.writeln();
    stderr.writeln(chalk.brightBlue('Waiting for approval of enrollment '
        '${request.enrollmentId} of $atSign'));
    try {
      await request.awaitApproval(
          retryInterval: approvalRetryInterval,
          maxRetries: AuthCliArgs.defaultApprovalRetries);
    } on AtException catch (e) {
      throw _reported(e);
    }
  }

  SecondaryAddressFinder _atDirectory() => CacheableSecondaryAddressFinder(
      atRootDomain.rootDomain, atRootDomain.rootPort);

  /// What an open that ended in [state] throws: the atServer's refusal, an
  /// atSign the atDirectory has no atServer for, or an atServer not reached
  /// within [maxConnectAttempts] tries.
  AtException _openFailure(AtConnectionState state) {
    if (state.isRefused) {
      return AtCredentialRefusedException(atSign, state);
    }
    if (state.cause == AtConnectionCause.noAtServer) {
      return SecondaryNotFoundException(
          '$atSign is not in the atDirectory at ${atRootDomain.rootDomain}: '
          'check the atSign, and that it has been activated');
    }
    return SecondaryServerConnectivityException(
        'Failed to connect within $maxConnectAttempts attempts: '
        '${state.outcome.name}'
        '${state.cause == null ? '' : ' (${state.cause!.name})'}');
  }

  /// [e], once written to stderr after the progress line.
  AtException _reported(AtException e) {
    stderr.writeln();
    stderr.writeln(chalk.brightRed(e.message));
    return e;
  }
}
