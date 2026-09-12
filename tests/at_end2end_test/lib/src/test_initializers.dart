// The flat keyfile fields are the legacy document's, which is the shape the
// demo atSigns' credentials take.
// ignore_for_file: deprecated_member_use

import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/src/at_encryption_key_initializers.dart';
import 'package:at_end2end_test/src/sync_initializer.dart';
import 'package:at_end2end_test/src/test_preferences.dart';
import 'package:at_end2end_test/utils/test_constants.dart';
import 'package:at_utils/at_logger.dart';

import 'at_credentials.dart';
import 'at_test_credentials.dart';

class TestSuiteInitializer {
  static final TestSuiteInitializer _singleton =
      TestSuiteInitializer._internal();

  static final AtSignLogger logger = AtSignLogger(' TestSuiteInitialized ');

  /// The key source each atSign was brought up from, keyed by atSign. Read by
  /// [switchToAtSign], which reopens the client from it.
  final Map<String, AtKeysIo> _keysCache = {};

  TestSuiteInitializer._internal() {
    AtSignLogger.root_level = 'info';
    _seedCredentialsForLocalRun();
    AtSignLogger.defaultLoggingHandler = AtSignLogger.consoleLoggingHandler;
  }

  factory TestSuiteInitializer.getInstance() {
    return _singleton;
  }

  /// The atSigns whose demo-credential keyfile this process has already
  /// seeded.
  final _seeded = <String>{};

  /// A durable key source for [atSign]: under `apkam` the login keyfile CI
  /// supplies, and under `pkam` a keyfile seeded once from the demo
  /// credentials. The client opens on it and files into it, so an nskey
  /// private or a retrofit outlives the client.
  ///
  /// ⚠️ Durable on purpose. Every atSign switch stops the outgoing client and
  /// opens a new one, and a private held only in the ring's memory goes with
  /// it: the next client adopts its own published advertisement holding no
  /// private for it, and every read of something sealed to that generation
  /// fails with "no nskey private held for ...".
  ///
  /// Seeded only when the keyfile is absent or holds no credential, since a
  /// keyfile that exists may already hold privates a re-seed would discard;
  /// one that holds no credential is filled in around whatever it holds.
  Future<AtKeysIo> _keysFor(
      String atSign, String authType, AtClientPreference preference) async {
    if (authType.toLowerCase() == 'apkam') {
      return FileAtKeysIo(
          filePath: (_) =>
              '${ConfigUtil.getYaml()['filePath']}/${atSign}_key.atKeys');
    }
    final keysIo = FileAtKeysIo(
        filePath: (a) => '${preference.hiveStoragePath}/$a.nskey.atKeys');
    if (_seeded.add(atSign)) {
      final demo = createAtKeysFromDemoKeys(atSign);
      AtKeys? existing;
      try {
        existing = await keysIo.read(atSign);
      } on Object {
        await keysIo.write(atSign, demo);
      }
      if (existing != null && !existing.holdsAuthenticationMaterial) {
        await keysIo.flush(
            Atsign(atSign),
            existing
              ..apkamPublicKey = demo.apkamPublicKey
              ..apkamPrivateKey = demo.apkamPrivateKey
              ..defaultEncryptionPublicKey = demo.defaultEncryptionPublicKey
              ..defaultEncryptionPrivateKey = demo.defaultEncryptionPrivateKey
              ..defaultSelfEncryptionKey = demo.defaultSelfEncryptionKey);
      }
    }
    return keysIo;
  }

  /// Brings [atSign] up on [manager], defaulting to the process-wide singleton.
  ///
  /// Pass a dedicated manager to keep this atSign's client alive alongside
  /// another's — see `ConcurrentClients`. On the singleton the outgoing
  /// client is stopped first, as switching always has, so two atSigns cannot
  /// both be live under it. [posture] is required and has no default, so the
  /// compiler names every caller. It is required even when
  /// [atClientPreference] is supplied — a preference built elsewhere already
  /// carries a posture, and one that disagrees with this is refused rather
  /// than silently preferred either way.
  ///
  /// The client is always rebuilt: any client already running as the
  /// principal the keys name is stopped, since `open` refuses a second one.
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

      bool apkam = authType.toLowerCase() == 'apkam';

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
      // preference it built itself, and this is the last point before the
      // client opens that every route has in common.
      TestPreferences.refuseDurableWritesToLongLivedAtSigns(
          atSign, atClientPreference);

      final keysIo = await _keysFor(atSign, authType, atClientPreference);
      _keysCache[atSign] = keysIo;
      if (apkam) {
        final authenticated = await keysIo.read(atSign);
        AtCredentials.credentialsMap[atSign] = {
          'pkamPublicKey': authenticated.apkamPublicKey,
          'pkamPrivateKey': authenticated.apkamPrivateKey,
          'encryptionPublicKey': authenticated.defaultEncryptionPublicKey,
          'encryptionPrivateKey': authenticated.defaultEncryptionPrivateKey,
          'selfEncryptionKey': authenticated.defaultSelfEncryptionKey
        };
      }

      final client = await _open(
          manager ?? AtClientManager.getInstance(), atSign, namespace, keysIo,
          atClientPreference);
      // Set Encryption Keys for currentAtSign
      await AtEncryptionKeysLoader.getInstance()
          .setEncryptionKeys(client, atSign);

      if (enableInitialSync) {
        await E2ESyncService.getInstance()
            .syncData(client.syncService, atSign: atSign);
      }

      // verify if the public key is in the local secondary
      var result =
          await client.getLocalSecondary()!.getEncryptionPublicKey(atSign);
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PUBLIC_KEY]
              .toString());

      // verify if the private key is in the local secondary
      result = await client.getLocalSecondary()!.getEncryptionPrivateKey();
      assert(result ==
          AtCredentials
              .credentialsMap[atSign]![TestConstants.ENCRYPTION_PRIVATE_KEY]
              .toString());
    } on Exception catch (e) {
      print('Exception in setting the encryption: $e');
      rethrow;
    }
  }

  /// Makes [atSign] current again, reopening its client from the key source
  /// its [testInitializer] brought it up from.
  ///
  /// **Why a switch back reopens.** The singleton holds one client, and a
  /// switch to another atSign stops the outgoing one; the switch back opens
  /// a fresh client on the same key source, which is what makes an APKAM
  /// enrollment authenticate again: the keys name it. Without a source to
  /// reopen from there is nothing to authenticate with, and that is refused
  /// here rather than left to fail as `AT0401` on the first verb.
  ///
  /// **Why only on a real switch.** The atSign already current is kept: a
  /// stop and reopen releases and reopens its store for nothing.
  ///
  /// [posture] is optional here, unlike on [testInitializer]: the atSign has
  /// already been brought up, so the preference it came up under is the
  /// answer. Naming one asks `TestPreferences` for that posture, which refuses
  /// if it disagrees with the preference already built.
  Future<AtClientManager> switchToAtSign(String atSign, String namespace,
      {AtClientPreference? preference, PqPosture? posture}) async {
    final acm = AtClientManager.getInstance();
    final pref = preference ?? _preferenceFor(atSign, posture);
    final current = _currentClientOf(acm);
    if (current != null &&
        current.getCurrentAtSign() == atSign &&
        !current.isStopped) {
      return acm;
    }
    final keysIo = _keysCache[atSign];
    if (keysIo == null) {
      throw StateError(
          'no key source has been built for $atSign, so a switch to it has '
          'nothing to open a client from. Call testInitializer for $atSign '
          'first.');
    }
    await _open(acm, atSign, namespace, keysIo, pref);
    return acm;
  }

  /// Opens [atSign]'s client on [keysIo] and makes it [manager]'s current
  /// one, stopping the client that was current and any client already
  /// running as the principal the keys name.
  Future<AtClient> _open(AtClientManager manager, String atSign,
      String namespace, AtKeysIo keysIo, AtClientPreference preference) async {
    await _currentClientOf(manager)?.stop();
    final principal = (await keysIo.read(atSign)).enrollmentToAuthenticateAs();
    for (final live in AtClientImpl.liveClientsFor(atSign)) {
      if (live.enrollmentId == principal) await live.stop();
    }
    final client = await Atsign(atSign)
        .open(keys: keysIo, preference: preference, namespace: namespace);
    manager.use(client);
    return client;
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

  /// The client [manager] currently holds, or null if it holds none.
  /// `AtClientManager.atClient` throws rather than returning null.
  AtClient? _currentClientOf(AtClientManager manager) {
    try {
      return manager.atClient;
    } on StateError {
      return null;
    }
  }

  /// Fills [AtCredentials.credentialsMap] from [AtTestCredentials] when CI has
  /// not filled it.
  ///
  /// `at_credentials.dart` is a four-line stub in every checkout — CI
  /// overwrites it from a secret — so on a developer machine that map is empty
  /// and [createAtKeysFromDemoKeys] throws a null check on its first line.
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

  /// The demo atSign's credentials as a legacy keyfile: the flat fields,
  /// naming no enrollment, which is what the atServer holds for it.
  ///
  /// NOTE: flat, never typed. Active typed rsa2048 authentication material
  /// reads as a retrofit already done, so a client under a PQ posture would
  /// refuse to upgrade from it.
  AtKeys createAtKeysFromDemoKeys(String atSign) {
    final credentials = AtCredentials.credentialsMap[atSign]!;
    return AtKeys()
      ..apkamPublicKey =
          AtBytes.fromString(credentials[TestConstants.PKAM_PUBLIC_KEY])
      ..apkamPrivateKey =
          AtBytes.fromString(credentials[TestConstants.PKAM_PRIVATE_KEY])
      ..defaultEncryptionPublicKey =
          AtBytes.fromString(credentials[TestConstants.ENCRYPTION_PUBLIC_KEY])
      ..defaultEncryptionPrivateKey =
          AtBytes.fromString(credentials[TestConstants.ENCRYPTION_PRIVATE_KEY])
      ..defaultSelfEncryptionKey =
          AtBytes.fromString(credentials[TestConstants.SELF_ENCRYPTION_KEY]);
  }
}
