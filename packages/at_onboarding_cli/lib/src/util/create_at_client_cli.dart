import 'dart:io';

import 'package:at_auth/at_auth_io.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli.dart';
import 'package:at_onboarding_cli/src/cli/auth_cli_args.dart';
import 'package:at_onboarding_cli/src/factory/service_factories.dart';
import 'package:at_onboarding_cli/src/util/at_onboarding_preference.dart';
import 'package:at_utils/at_utils.dart';
import 'package:chalkdart/chalk.dart';

import 'home_directory_util.dart';

/// A client for the commands that only read or administer an atSign — `otp`,
/// `list`, `spp`, `approve` and the rest — opened from its keyfile and made
/// the manager's current client.
///
/// The connection is given [maxConnectAttempts] tries, three seconds apart,
/// to come online; a client the atServer refuses, or that is still offline
/// after that, is stopped and an [UnAuthenticatedException] says so.
///
/// [waitForPqStartup] holds the command until the client's post-quantum
/// startup has finished, bounded by [startupTailBound]; a command that reads
/// what that startup leaves behind needs it, one that sends a single verb and
/// exits does not.
///
/// [posture] is how far into the post-quantum rollout this invocation runs;
/// null means whatever the at_client this was built against defaults to.
Future<AtClient> createAtClient(
    {required String atSign,
    String? atKeysFilePath,
    String? rootDomain,
    String? passPhrase,
    PqPosture? posture,
    bool waitForPqStartup = true,
    int maxConnectAttempts = 5}) async {
  const nameSpace = 'at_activate';
  const retryInterval = Duration(seconds: 3);
  atSign = AtUtils.fixAtSign(atSign);
  final homeDir = HomeDirectoryUtil.homeDir;

  storageDir = HomeDirectoryUtil.standardAtClientStorageDir(
    atSign: atSign,
    progName: nameSpace,
    uniqueID: '${DateTime.now().millisecondsSinceEpoch}',
  );

  // With no path given, the keyfile is looked for in the home directory's
  // keys folder.
  final atKeysFilePathToUse =
      (atKeysFilePath ?? '$homeDir/.atsign/keys/${atSign}_key.atKeys')
          .replaceAll('/', Platform.pathSeparator);
  final downloadPathToUse = ('$homeDir!/.atsign/downloads/$atSign/$nameSpace')
      .replaceAll('/', Platform.pathSeparator);
  final parsedRootDomain =
      AtRootDomain.parse(rootDomain ?? AuthCliArgs.defaultAtDirectoryFqdn);

  final AtOnboardingPreference preference = AuthCliArgs.preferenceUnder(posture)
    ..atKeysFilePath = atKeysFilePathToUse
    ..namespace = nameSpace
    ..rootDomain = parsedRootDomain.rootDomain
    ..rootPort = parsedRootDomain.rootPort
    ..passPhrase = passPhrase
    ..storagePath = storageDir?.path
    ..downloadPath = downloadPathToUse;

  stderr.write(chalk.brightBlue('\r\x1b[KConnecting ... '));
  final AtClient client;
  try {
    client = await Atsign(atSign).open(
        keys: FileAtKeysIo(
            filePath: (_) => atKeysFilePathToUse, passPhrase: passPhrase),
        preference: preference,
        storage: preference.storageFor(atSign),
        serviceFactory: ServiceFactoryWithNoOpSyncService());
  } on AtOpenRefusedException catch (e) {
    stderr.writeln(chalk.brightRed(e.message));
    throw UnAuthenticatedException(e.message);
  }
  final state = await client.connection.awaitOnline(
      budget: retryInterval * maxConnectAttempts, retryInterval: retryInterval);
  if (!state.isOnline) {
    await client.stop();
    stderr.writeln();
    final msg = 'Failed to connect within $maxConnectAttempts attempts: '
        '${state.outcome.name}'
        '${state.cause == null ? '' : ' (${state.cause!.name})'}';
    stderr.writeln(chalk.brightRed(msg));
    throw UnAuthenticatedException(msg);
  }
  stderr.writeln(chalk.brightGreen('Connected'));
  AtClientManager.getInstance().use(client);
  if (waitForPqStartup) await awaitStartupTail(client);
  return client;
}

/// How long a command waits for the client's post-quantum startup to finish.
const Duration startupTailBound = Duration(seconds: 30);
