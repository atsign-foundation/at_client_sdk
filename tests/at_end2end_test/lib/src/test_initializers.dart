import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_utils/at_logger.dart';

import 'at_credentials.dart';

class TestSuiteInitializer {
  static final TestSuiteInitializer _singleton =
      TestSuiteInitializer._internal();

  static final AtSignLogger logger = AtSignLogger(' TestSuiteInitialized ');

  TestSuiteInitializer._internal() {
    AtSignLogger.root_level = 'info';
    AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;
  }

  factory TestSuiteInitializer.getInstance() {
    return _singleton;
  }

  /// The atSigns whose nskey keyfile this process has already seeded.
  final _seeded = <String>{};

  /// A durable key source for [atSign], so nskey privates outlive the client.
  ///
  /// ⚠️ **Supplied HERE and nowhere later, because it cannot be.**
  /// `AtClientImpl.create` memoises one client per atSign in
  /// `atClientInstanceMap` and assigns `_atKeysIo` only while constructing, so
  /// a later `setCurrentAtSign(..., atKeysIo: ...)` hands it to a cached
  /// instance that ignores it. This is the first construction, and therefore
  /// the only place it takes effect.
  ///
  /// Without it `PqClientBootstrap` gets `keysIo: null`, builds no
  /// `NskeyPrivateFiling`, and every nskey private lives only in the ring's
  /// memory — which the e2e suites discard constantly, because each atSign
  /// switch stops the outgoing client and builds a new one. A client would
  /// then adopt its own published advertisement holding no private for it, and
  /// every read of something sealed to that generation fails with "no nskey
  /// private held for ...". That is not a property of the product: it is what
  /// a client with no key source is documented to be, and an application has
  /// one.
  ///
  /// Seeded once per atSign and only when absent. `NskeyPrivateFiling.read`
  /// answers null on any read failure, so a keyfile that does not exist looks
  /// exactly like one holding no private — and re-seeding would discard every
  /// private already filed, which is the whole point of it being durable.
  Future<AtKeysIo> _nskeyKeyfileFor(
      String atSign, AtClientPreference preference) async {
    final keysIo = FileAtKeysIo(
        filePath: (a) => '${preference.hiveStoragePath}/$a.nskey.atKeys');
    if (_seeded.add(atSign)) {
      try {
        await keysIo.read(atSign);
      } on Object {
        await keysIo.write(atSign, AtKeys());
      }
    }
    return keysIo;
  }

  /// Brings [atSign] up on [manager], defaulting to the process-wide singleton.
  ///
  /// Pass a dedicated manager to keep this atSign's client alive alongside
  /// another's — see `ConcurrentClients`. The singleton stops the outgoing
  /// client on every switch, so two atSigns cannot both be live under it.
  Future<void> testInitializer(String atSign, String namespace, String authType,
      {bool enableInitialSync = true,
      AtClientPreference? atClientPreference,
      AtClientManager? manager}) async {
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
      // Create the atClientManager for the atSign
      var atClientManager = await (manager ?? AtClientManager.getInstance())
          .setCurrentAtSign(atSign, namespace, atClientPreference,
              atChops: atChops,
              atKeysIo: await _nskeyKeyfileFor(atSign, atClientPreference),
              enrollmentId: atAuthResponse?.atAuthKeys?.enrollmentId);
      // Set Encryption Keys for currentAtSign
      await AtEncryptionKeysLoader.getInstance()
          .setEncryptionKeys(atClientManager.atClient, atSign);

      if (enableInitialSync) {
        await E2ESyncService.getInstance().syncData(
            atClientManager.atClient.syncService,
            atSign: atSign);
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
