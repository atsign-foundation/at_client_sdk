import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/functional_storage.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:crypto/crypto.dart';
import 'package:at_client/at_client.dart';

import 'package:at_demo_data/at_demo_data.dart';
import 'package:test/test.dart';

class TestUtils {
  static AtSignLogger logger = AtSignLogger(' TestUtils ');

  /// Root server port for the virtualenv under test. Defaults to 64; a
  /// base-port virtualenv (set VIRTUALENV_BASE_PORT, e.g. via runLocal.sh)
  /// puts the root server at the base port itself.
  static int get rootServerPort =>
      int.tryParse(Platform.environment['VIRTUALENV_BASE_PORT'] ?? '') ?? 64;

  static FunctionalStorage? _storage;

  /// Names this test file, giving its clients storage no other file opens.
  ///
  /// Call once, first thing in `main()`. Every bundle it hands out is closed
  /// in a `tearDownAll` registered here, since these bundles are borrowed and
  /// the client only detaches from them.
  static void isolateStorage(String testFile) {
    final storage = FunctionalStorage(testFile);
    _storage = storage;
    tearDownAll(() async {
      await storage.closeAll();
      if (identical(_storage, storage)) _storage = null;
    });
  }

  /// This file's storage. Throws rather than falling back to a shared one:
  /// silently sharing is what [isolateStorage] exists to stop.
  static FunctionalStorage get storage =>
      _storage ??
      (throw StateError('this test file has not called '
          'TestUtils.isolateStorage(<file name>) at the top of main(), so it '
          'has no storage of its own'));

  /// The bundle every client this file builds for [atSign] shares.
  static AtClientStorage storageFor(String atSign) =>
      storage.forAtSign(atSign);

  /// A preference carrying no storage path: what opens the store is the
  /// bundle passed to `setCurrentAtSign`, and a call site that forgets one
  /// fails loudly here rather than quietly opening the shared directory.
  static AtClientPreference getPreference(String atsign) {
    var preference = AtClientPreference();
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

  /// [storage] overrides this file's bundle, for a caller that has none —
  /// a child isolate is a fresh heap, so [isolateStorage]'s static is null
  /// there and the isolate has to build its own from what it was handed.
  static Future<AtClientManager> initAtClient(
      String currentAtSign, String namespace,
      {AtClientPreference? preference, AtClientStorage? storage}) async {
    AtSignLogger.root_level = 'shout';
    preference ??= TestUtils.getPreference(currentAtSign);
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, preference,
        atChops: encryptionKeysLoader.createAtChopsFromDemoKeys(currentAtSign),
        storage: storage ?? storageFor(currentAtSign));
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
