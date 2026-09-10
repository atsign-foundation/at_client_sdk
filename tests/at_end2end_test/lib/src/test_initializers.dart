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
import 'at_test_credentials.dart';

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
    _seedCredentialsForLocalRun();
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
  /// memory — which each atSign switch discards, since it stops the outgoing
  /// client and builds a new one. Such a client adopts its own published
  /// advertisement holding no private for it, and every read of something
  /// sealed to that generation fails with "no nskey private held for ...".
  ///
  /// Seeded once per atSign and only when absent: `NskeyPrivateFiling.read`
  /// answers null on any read failure, so a keyfile that does not exist looks
  /// exactly like one holding no private, and re-seeding would discard every
  /// private already filed.
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
  /// [posture] is required and has no default, so the compiler names every
  /// caller. It is required even when [atClientPreference] is supplied — a
  /// preference built elsewhere already carries a posture, and one that
  /// disagrees with this is refused rather than silently preferred either way.
  ///
  /// ⛔ See `TestPreferences.getPreference` for why the choice matters on this
  /// pack's long-lived atSigns.
  Future<void> testInitializer(String atSign, String namespace, String authType,
      {required PqPosture posture,
      bool enableInitialSync = true,
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

      if (atClientPreference != null && atClientPreference.posture != posture) {
        throw ArgumentError(
            'the supplied AtClientPreference for $atSign was built at a '
            'different posture from the one named here. AtClientPreference '
            'holds it final, so this call cannot change it — pass the posture '
            'the preference was built with, or build the preference at the '
            'posture you want.');
      }
      atClientPreference ??=
          TestPreferences.getInstance().getPreference(atSign, posture: posture);
      // Checked here as well as inside getPreference: a caller may hand in a
      // preference it built itself, and this is the last point before
      // setCurrentAtSign that every route has in common.
      TestPreferences.refuseDurableWritesToLongLivedAtSigns(
          atSign, atClientPreference);
      // Remember what this atSign authenticated with. Switching away and back
      // rebuilds the client, and a rebuild with no credentials cannot
      // authenticate an APKAM enrollment - see [switchToAtSign].
      _authCache[atSign] =
          _AuthCredentials(atChops, atAuthResponse?.atAuthKeys?.enrollmentId);
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
        await E2ESyncService.getInstance()
            .syncData(atClientManager.atClient.syncService, atSign: atSign);
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
  ///
  /// [posture] is optional here, unlike on [testInitializer]: the atSign has
  /// already been brought up, so the preference it came up under is the
  /// answer. Naming one asks `TestPreferences` for that posture, which refuses
  /// if it disagrees with the preference already built.
  Future<AtClientManager> switchToAtSign(String atSign, String namespace,
      {AtClientPreference? preference, PqPosture? posture}) async {
    final acm = AtClientManager.getInstance();
    final pref = preference ?? _preferenceFor(atSign, posture);
    if (_currentAtSign() == atSign) {
      return acm.setCurrentAtSign(atSign, namespace, pref);
    }
    final credentials = _authCache[atSign];
    // The nskey keyfile too: a rebuild without it holds no filing, so every
    // private the earlier client minted is unreachable and a published
    // generation is adopted with no private half.
    return acm.setCurrentAtSign(atSign, namespace, pref,
        atChops: credentials?.atChops,
        atKeysIo: await _nskeyKeyfileFor(atSign, pref),
        enrollmentId: credentials?.enrollmentId);
  }

  /// The preference [atSign] was brought up under, or one built at [posture]
  /// when a switch names one.
  ///
  /// `AtClientPreference.posture` is final and decides what a client mints and
  /// publishes on the atSign, so a posture is never invented here: a switch
  /// back reuses what `testInitializer` chose.
  AtClientPreference _preferenceFor(String atSign, PqPosture? posture) {
    final preferences = TestPreferences.getInstance();
    if (posture != null) {
      return preferences.getPreference(atSign, posture: posture);
    }
    final existing = preferences.atClientPreferencesMap[atSign];
    if (existing == null) {
      throw StateError(
          'no preference has been built for $atSign, so a switch to it has no '
          'posture to run at. Call testInitializer for $atSign first, or name '
          'a posture here.');
    }
    return existing;
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

  /// Fills [AtCredentials.credentialsMap] from [AtTestCredentials] when CI has
  /// not filled it.
  ///
  /// `at_credentials.dart` is a four-line stub in every checkout — CI
  /// overwrites it from a secret — so on a developer machine that map is empty
  /// and `createAtChopsFromDemoKeys` throws a null check on its first line.
  ///
  /// Guarded on empty, so CI is untouched: there the map already holds the
  /// atSigns the secret supplied, and this does nothing.
  ///
  /// [AtTestCredentials] is the source rather than `at_demo_data` directly: it
  /// already curates exactly this map for exactly these atSigns, and
  /// re-deriving it here would make two places answer the same question.
  static void _seedCredentialsForLocalRun() {
    if (AtCredentials.credentialsMap.isNotEmpty) return;
    AtCredentials.credentialsMap.addAll(AtTestCredentials.credentialsMap);
    logger.info('AtCredentials was empty, so this is a local run: seeded '
        '${AtCredentials.credentialsMap.length} demo atSign(s) from '
        'AtTestCredentials');
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
