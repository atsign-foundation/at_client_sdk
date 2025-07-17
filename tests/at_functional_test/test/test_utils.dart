import 'dart:convert';
import 'dart:typed_data';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:crypto/crypto.dart';
import 'package:at_client/at_client.dart';

import 'package:at_demo_data/at_demo_data.dart';

class TestUtils {
  static final ObjectLifeCycleOptions optionsTtlOneMinute =
      ObjectLifeCycleOptions(timeToLive: Duration(minutes: 1));

  static AtSignLogger logger = AtSignLogger(' TestUtils ');

  static AtClientPreference getPreference(String atsign) {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'test/hive/client/$atsign';
    preference.commitLogPath = 'test/hive/client/$atsign';
    preference.isLocalStoreRequired = true;
    preference.rootDomain = 'vip.ve.atsign.zone';
    preference.decryptPackets = false;
    preference.pathToCerts = 'test/testData/cert.pem';
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

  static Future<AtClientManager> initAtClient(
      String currentAtSign, String namespace,
      {AtClientPreference? preference}) async {
    AtSignLogger.root_level = 'shout';
    preference ??= TestUtils.getPreference(currentAtSign);
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, preference,
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
