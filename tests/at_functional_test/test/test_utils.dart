import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:crypto/crypto.dart';
import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/at_client.dart';

import 'package:at_demo_data/at_demo_data.dart';

class TestUtils {
  static AtSignLogger logger = AtSignLogger(' TestUtils ');

  /// Root server port for the virtualenv under test. Defaults to 64; a
  /// base-port virtualenv (set VIRTUALENV_BASE_PORT, e.g. via runLocal.sh)
  /// puts the root server at the base port itself.
  static int get rootServerPort =>
      int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '') ?? 64;

  /// [posture] and [signingRollout] must be threaded here because both are
  /// final at construction — a test cannot set either on the returned
  /// instance.
  static AtClientPreference getPreference(String atsign,
      {ReleasePosture? posture, SigningRollout? signingRollout}) {
    var preference = posture == null && signingRollout == null
        ? AtClientPreference()
        : AtClientPreference(
            posture: posture ?? const ReleasePosture.migration(),
            signingRollout: signingRollout);
    preference.hiveStoragePath = 'test/hive/client/$atsign';
    preference.commitLogPath = 'test/hive/client/$atsign';
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.rootPort = rootServerPort;
    preference.decryptPackets = false;
    preference.tlsKeysSavePath = 'test/tlsKeysFile';
    preference.fetchOfflineNotifications = true;
    return preference;
  }

  static String generatePKAMDigest(String atSign, String challenge) {
    var privateKey = pkamPrivateKeyMap[atSign]!;
    privateKey = privateKey.trim();
    var key = RSAPrivateKey.fromString(privateKey);
    challenge = challenge.trim();
    var sign =
        key.createSHA256Signature(Uint8List.fromList(utf8.encode(challenge)));
    return base64Encode(sign);
  }

  static String generateCramDigest(String atSign, String challenge) {
    var cramSecret = cramKeyMap[atSign];
    var combo = '$cramSecret$challenge';
    var bytes = utf8.encode(combo);
    var digest = sha512.convert(bytes);
    return digest.toString();
  }

  /// [atKeysIo] is threaded through for tests of anything that reads key
  /// material from `AtClient.atKeysIo` — the signing root's private half is the
  /// first. Without one that getter is null, so such a test would assert
  /// against a client structurally unable to hold the key and pass or fail for
  /// reasons having nothing to do with the code under test.
  ///
  /// Supplying it also forces `setCurrentAtSign` past its same-atSign
  /// short-circuit, which checks for exactly these override arguments — so it
  /// reaches the client rather than being dropped on an already-current atSign.
  static Future<AtClientManager> initAtClient(
      String currentAtSign, String namespace,
      {AtClientPreference? preference, AtKeysIo? atKeysIo}) async {
    // `info`, matching the e2e pack (`test_initializers.dart`), not `shout`.
    //
    // At `shout` the client's own account of what it did is filtered out
    // before it reaches the run's output — including `warning`, which is the
    // level a notification dropped in the delivery loop logs at. A drop and a
    // non-arrival then print the same nothing, and the failure gets attributed
    // to whichever side the reader guesses. That cost most of an evening on
    // `nskey_self_notify_live_test.dart`: three hypotheses about the atServer,
    // all wrong, while the reason sat in a `warning` line nobody could see.
    //
    // A test wanting the monitor's frame-by-frame detail still has to ask for
    // `finest` — and must do so AFTER this call, which resets the level.
    AtSignLogger.root_level = 'info';
    preference ??= TestUtils.getPreference(currentAtSign);
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, preference,
        atKeysIo: atKeysIo,
        atChops: encryptionKeysLoader.createAtChopsFromDemoKeys(currentAtSign));
    // Set the preferences again because (1) setCurrentAtSign might do nothing
    // because currentAtSign is the same, and (2) some other test may have messed
    // with the preferences
    atClientManager.atClient.setPreferences(preference);
    // To setup encryption keys
    await encryptionKeysLoader.setEncryptionKeys(
        atClientManager.atClient, currentAtSign);
    return atClientManager;
  }

  static String formatCommand(String command) {
    if (!command.contains('\n')) return '$command\n';
    return command;
  }

  static Future<String?> executeCommandAndParse(AtClient? client, command,
      {bool auth = false, RemoteSecondary? remoteSecondary}) async {
    remoteSecondary ??= client?.getRemoteSecondary();
    command = formatCommand(command);
    logger.info('SENDING: $command');
    String? response = await remoteSecondary?.executeCommand(
      command,
      auth: auth,
    );
    logger.info('RECEIVED: $response');
    return response?.replaceFirst('data:', '');
  }
}
