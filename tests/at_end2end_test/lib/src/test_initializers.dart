import 'package:at_auth/at_auth.dart';
import 'package:at_auth/at_auth_io.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_utils/at_logger.dart';

import 'at_credentials.dart';

/// What an atSign's initial authentication produced, kept so that switching
/// back to that atSign later can be given the same credentials again.
class _AuthCredentials {
  final AtChops atChops;
  final String? enrollmentId;

  _AuthCredentials(this.atChops, this.enrollmentId);
}

class TestSuiteInitializer {
  static final TestSuiteInitializer _singleton =
      TestSuiteInitializer._internal();

  static final AtSignLogger logger = AtSignLogger(' TestSuiteInitialized ');

  /// The credentials [testInitializer] authenticated each atSign with, keyed
  /// by atSign. Read by [switchToAtSign].
  final Map<String, _AuthCredentials> _authCache = {};

  TestSuiteInitializer._internal() {
    AtSignLogger.root_level = 'info';
    AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;
  }

  factory TestSuiteInitializer.getInstance() {
    return _singleton;
  }

  Future<void> testInitializer(String atSign, String namespace, String authType,
      {bool enableInitialSync = true,
      AtClientPreference? atClientPreference}) async {
    try {
      logger.info(
          'testInitialized called for $atSign $namespace $authType $enableInitialSync $atClientPreference');
      late AtChops atChops;
      AtAuthResponse? atAuthResponse;

      bool apkam = authType.toLowerCase() == 'apkam';

      if (apkam) {
        AtAuthRequest atAuthRequest = AtAuthRequest(
          atSign,
          atKeysIo: FileAtKeysIo(
              filePath: (_) =>
                  '${ConfigUtil.getYaml()['filePath']}/${atSign}_key.atKeys'),
        );
        atAuthRequest.rootDomain = AtRootDomain(
            ConfigUtil.getYaml()['root_server']['url'],
            ConfigUtil.getYaml()['root_server']['port'] ?? 64);
        atAuthResponse = await authenticate(atAuthRequest);
        atChops = createAtChopsFromAtAuthKeys(atAuthResponse.atAuthKeys!);

        AtCredentials.credentialsMap[atSign] = {
          'pkamPublicKey': atAuthResponse.atAuthKeys!.apkamPublicKey,
          'pkamPrivateKey': atAuthResponse.atAuthKeys!.apkamPrivateKey,
          'encryptionPublicKey':
              atAuthResponse.atAuthKeys!.defaultEncryptionPublicKey,
          'encryptionPrivateKey':
              atAuthResponse.atAuthKeys!.defaultEncryptionPrivateKey,
          'selfEncryptionKey':
              atAuthResponse.atAuthKeys!.defaultSelfEncryptionKey
        };
      } else {
        atChops = createAtChopsFromDemoKeys(atSign);
      }

      atClientPreference ??=
          TestPreferences.getInstance().getPreference(atSign);
      // Remember what this atSign authenticated with. Switching away and back
      // rebuilds the client, and a rebuild with no credentials cannot
      // authenticate an APKAM enrollment - see [switchToAtSign].
      _authCache[atSign] =
          _AuthCredentials(atChops, atAuthResponse?.atAuthKeys?.enrollmentId);
      // Create the atClientManager for the atSign
      var atClientManager = await AtClientManager.getInstance()
          .setCurrentAtSign(atSign, namespace, atClientPreference,
              atChops: atChops,
              enrollmentId: atAuthResponse?.atAuthKeys?.enrollmentId);
      // Set Encryption Keys for currentAtSign
      await AtEncryptionKeysLoader.getInstance()
          .setEncryptionKeys(atClientManager.atClient, atSign);

      if (enableInitialSync) {
        await E2ESyncService.getInstance()
            .syncData(atClientManager.atClient.syncService);
      }

      // verify if the public key is in the local secondary
      var result = await atClientManager.atClient
          .getLocalSecondary()!
          .getEncryptionPublicKey(atSign);
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]
              .toString());

      // verify if the private key is in the local secondary
      result = await atClientManager.atClient
          .getLocalSecondary()!
          .getEncryptionPrivateKey();
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]
              .toString());
    } on Exception catch (e) {
      print('Exception in setting the encryption: $e');
      rethrow;
    }
  }

  /// Makes [atSign] current again, re-supplying the credentials its initial
  /// [testInitializer] authentication produced.
  ///
  /// **Why the credentials have to be repeated.** `setCurrentAtSign` for an
  /// atSign other than the current one stops that client and builds a fresh
  /// one, and it keeps no credentials of its own: called with only a
  /// preference, it builds a client with no `AtChops` and a null
  /// `enrollmentId`. Under `authType: apkam` the atKeys carry a real
  /// enrollment id, the atServer expects PKAM to name it, and the rebuilt
  /// client cannot - which is `AT0401 pkam authentication failed`, the whole
  /// of `end2end_test_14`. It is invisible under `authType: pkam` and against
  /// the local fixture, both of which authenticate with a null enrollment id.
  ///
  /// **Why only on a real switch.** `setCurrentAtSign`'s idempotency
  /// short-circuit requires `atChops` and `enrollmentId` to be null, so
  /// passing them for the atSign already current would force a stop/recreate
  /// on every call - and a stopped client releases its storage, so each no-op
  /// switch would reopen the store cold.
  Future<AtClientManager> switchToAtSign(String atSign, String namespace,
      {AtClientPreference? preference}) async {
    final acm = AtClientManager.getInstance();
    final pref =
        preference ?? TestPreferences.getInstance().getPreference(atSign);
    if (_currentAtSign() == atSign) {
      return acm.setCurrentAtSign(atSign, namespace, pref);
    }
    final credentials = _authCache[atSign];
    return acm.setCurrentAtSign(atSign, namespace, pref,
        atChops: credentials?.atChops, enrollmentId: credentials?.enrollmentId);
  }

  /// The atSign the manager currently holds, or null if it holds no client.
  /// `AtClientManager.atClient` throws rather than returning null.
  String? _currentAtSign() {
    try {
      return AtClientManager.getInstance().atClient.getCurrentAtSign();
    } on StateError {
      return null;
    }
  }

  Future<AtAuthResponse> authenticate(AtAuthRequest atAuthRequest) async {
    AtAuth atAuth = AtAuth.create();
    AtAuthResponse atAuthResponse = await atAuth.authenticate(atAuthRequest);
    return atAuthResponse;
  }

  AtChops createAtChopsFromAtAuthKeys(AtKeys atAuthKeys) {
    AtEncryptionKeyPair atEncryptionKeyPair = AtEncryptionKeyPair.create(
        atAuthKeys.defaultEncryptionPublicKey!.toString(),
        atAuthKeys.defaultEncryptionPrivateKey!.toString());
    AtPkamKeyPair atPkamKeyPair = AtPkamKeyPair.create(
        atAuthKeys.apkamPublicKey!.toString(),
        atAuthKeys.apkamPrivateKey!.toString());
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AESKey(atAuthKeys.defaultSelfEncryptionKey!.toString());
    atChopsKeys.apkamSymmetricKey =
        AESKey(atAuthKeys.apkamSymmetricKey!.toString());

    AtChops atChops = AtChopsImpl(atChopsKeys);
    return atChops;
  }

  AtChops createAtChopsFromDemoKeys(String atSign) {
    var atEncryptionKeyPair = AtEncryptionKeyPair.create(
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY],
        AtCredentials
            .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]);
    var atPkamKeyPair = AtPkamKeyPair.create(
        AtCredentials.credentialsMap[atSign]![TestConstants.PKAM_PUBLIC_KEY],
        AtCredentials.credentialsMap[atSign]![TestConstants.PKAM_PRIVATE_KEY]);
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey = AESKey(AtCredentials
        .credentialsMap[atSign]![TestConstants.SELF_ENCRYPTION_KEY]);
    return AtChopsImpl(atChopsKeys);
  }
}
