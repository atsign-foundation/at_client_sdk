import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:at_functional_test/src/at_keys_initializer.dart';
import 'package:at_functional_test/src/functional_storage.dart';
import 'package:at_utils/at_logger.dart';
import 'package:crypton/crypton.dart';
import 'package:crypto/crypto.dart';
import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service_impl.dart';

import 'package:at_demo_data/at_demo_data.dart';
import 'package:test/test.dart';

/// Legacy in every axis but with the post-quantum providers configured — the
/// combination the post-quantum tests in this pack need, and one no deployment
/// should have.
///
/// Deliberately not one of `PqPosture`'s named constants: the rollout ladder
/// does not offer it as a stage.
final legacyPlusPqProviders = PqPosture(
  authenticationKeyAlgorithm: PqPosture.legacy.authenticationKeyAlgorithm,
  dataSigningKeyAlgorithms: PqPosture.legacy.dataSigningKeyAlgorithms,
  seedNamespaceKeys: PqPosture.legacy.seedNamespaceKeys,
  keyExchangeMode: PqPosture.legacy.keyExchangeMode,
  writesPqByDefault: PqPosture.legacy.writesPqByDefault,
  configuresPqProviders: true,
  disallowLegacyEncryption: PqPosture.legacy.disallowLegacyEncryption,
  mintLegacyMaterial: PqPosture.legacy.mintLegacyMaterial,
  sealsToKeyAlgorithms: PqPosture.legacy.sealsToKeyAlgorithms,
  keyEstablishmentAlgorithms: PqPosture.legacy.keyEstablishmentAlgorithms,
);

/// Waits until [notifications] reports a listening monitor on BOTH of its
/// public signals: `currentListenerStateStream` has emitted `listening`, and
/// `currentListenerState` reads `listening`.
///
/// `subscribe()` returns long before the monitor's socket has connected,
/// authenticated and written `monitor:`, and the atServer's inbound stream is
/// a broadcast with no backlog - so a notification created in that window is
/// never delivered on that connection and the send still reports `delivered`.
/// A gate is therefore mandatory before notifying anything.
///
/// Requiring both is what makes it a gate rather than a glimpse: the stream
/// is where the transition is observable, and the state is what a caller
/// reads afterwards. An emission followed by an immediate drop would satisfy
/// the stream alone.
///
/// ⚠️ What this proves is that at_lookup got `monitor:` out without error,
/// NOT that the atServer registered it - the atServer answers `monitor:` with
/// nothing at all, so no client can currently tell the two apart. Accepted
/// deliberately (gkc, 2026-09-10) rather than keep paying for the gate that
/// was sufficient: waiting for a notification to actually arrive, where the
/// only guaranteed one is the atServer's stats tick every 15s, cost ~7.5s a
/// time and was the largest single cost in this pack.
/// atsign-foundation/at_server#2764 makes `monitor:` answerable, and that is
/// what turns this back into a proof.
Future<void> awaitMonitorListening(NotificationServiceImpl notifications,
    {Duration timeout = const Duration(seconds: 60)}) async {
  bool stateIsListening() =>
      notifications.currentListenerState ==
      NotificationListenerState.listening;

  final reached = Completer<void>();
  // Attached BEFORE the state is read, so a transition landing between the
  // two is caught here rather than waited for forever.
  final sub = notifications.currentListenerStateStream.listen((state) {
    if (state == NotificationListenerState.listening &&
        stateIsListening() &&
        !reached.isCompleted) {
      reached.complete();
    }
  });
  try {
    // Already listening: the emission happened before this call, and the
    // state is the durable half of the same fact.
    if (stateIsListening()) return;
    await reached.future.timeout(timeout,
        onTimeout: () => throw StateError(
            'the monitor never reached `listening` within $timeout, so '
            'at_lookup never got `monitor:` out; notifying now would repeat '
            'the race this gate exists to close'));
  } finally {
    await sub.cancel();
  }
}

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
  /// Call once, first thing in `main()`. A `tearDownAll` registered here stops
  /// every client still running in the isolate and then closes every bundle
  /// it handed out, since these bundles are borrowed and a client only
  /// detaches from them.
  static void isolateStorage(String testFile) {
    final storage = FunctionalStorage(testFile);
    _storage = storage;
    tearDownAll(() async {
      // NOTE: a client stopped after its store closed keeps syncing into
      // `Box not found` until the isolate dies, so stop before closing.
      for (final client in List.of(AtClientImpl.atClientInstanceMap.values)) {
        await client.stop();
      }
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
  static AtClientStorage storageFor(String atSign) => storage.forAtSign(atSign);

  /// A bundle for a second live principal on [atSign] — an enrolled client
  /// running beside the owner client that approved it. See
  /// [FunctionalStorage.forPrincipal] for why a retrofit does NOT come here.
  static AtClientStorage storageForPrincipal(String atSign, String label) =>
      storage.forPrincipal(atSign, label);

  /// Whatever `AtClientPreference` currently defaults its posture to.
  ///
  /// For the tests whose subject IS that default, and only those: it follows
  /// the SDK, so a release moving the default moves what such a test
  /// exercises.
  static PqPosture get sdkDefaultPosture => AtClientPreference().posture;

  /// A preference for [atsign] at [posture], carrying no storage path: what
  /// opens the store is the bundle passed to `setCurrentAtSign`, so a call
  /// site that forgets one fails loudly there rather than quietly opening the
  /// shared directory.
  ///
  /// [keyEstablishmentAlgorithms] is what this atSign mints and advertises;
  /// [sealsToKeyAlgorithms] is the order in which, as a sender, it picks among
  /// the keys a recipient advertises.
  ///
  /// ⚠️ One atSign in one process holds one posture: every axis here is final
  /// at construction and `setCurrentAtSign` refuses a preference differing
  /// from the running client's, so two tests sharing an atSign share a
  /// posture.
  static AtClientPreference getPreference(String atsign,
      {required PqPosture posture,
      SigningAlgoType? authenticationKeyAlgorithm,
      Set<SigningAlgoType>? dataSigningKeyAlgorithms,
      List<String>? keyEstablishmentAlgorithms,
      List<String>? sealsToKeyAlgorithms}) {
    var preference = AtClientPreference(
        posture: posture,
        authenticationKeyAlgorithm: authenticationKeyAlgorithm,
        dataSigningKeyAlgorithms: dataSigningKeyAlgorithms,
        keyEstablishmentAlgorithms: keyEstablishmentAlgorithms,
        sealsToKeyAlgorithms: sealsToKeyAlgorithms);
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

  /// Builds this file's client for [currentAtSign] in [namespace] at
  /// [posture], with its encryption keys loaded.
  ///
  /// A [preference] built at a different posture is refused rather than
  /// silently winning; passing [atKeysIo] also forces `setCurrentAtSign` past
  /// its same-atSign short-circuit; and [storage] is for a caller with no
  /// file-level bundle, such as a child isolate, where [isolateStorage]'s
  /// static is null.
  static Future<AtClientManager> initAtClient(
      String currentAtSign, String namespace,
      {required PqPosture posture,
      AtClientPreference? preference,
      AtKeysIo? atKeysIo,
      AtClientStorage? storage}) async {
    // NOTE: `shout` hides `warning`, the level at which a notification dropped
    // in the delivery loop logs, making a drop and a non-arrival print the same
    // nothing. A test wanting the monitor's frame-by-frame detail must set
    // `finest` AFTER this call, which resets the level.
    AtSignLogger.root_level = 'info';
    if (preference != null && preference.posture != posture) {
      throw ArgumentError(
          'the supplied AtClientPreference for $currentAtSign was built at a '
          'different posture from the one named here. Every posture axis is '
          'final at construction, so this call cannot reconcile them — name '
          'the posture the preference was built with, or build it at the '
          'posture you want.');
    }
    preference ??= TestUtils.getPreference(currentAtSign, posture: posture);
    final encryptionKeysLoader = AtEncryptionKeysLoader.getInstance();
    var atClientManager = await AtClientManager.getInstance().setCurrentAtSign(
        currentAtSign, namespace, preference,
        atKeysIo: atKeysIo,
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
