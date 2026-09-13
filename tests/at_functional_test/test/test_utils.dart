// PqStartupGates is @experimental; this pack's PQ files drive that
// substrate deliberately.
// ignore_for_file: experimental_member_use

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
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
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
/// time and was the largest single cost in this pack. Nothing here depends on
/// an atServer version: `listening` means the same against every one of them.
/// What would turn this back into a proof is an atServer that answers
/// `monitor:` at all.
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
  /// opens the store is the bundle passed to `open`, so a call site that
  /// forgets one fails loudly there rather than quietly opening the shared
  /// directory.
  ///
  /// [keyEstablishmentAlgorithms] is what this atSign mints and advertises;
  /// [sealsToKeyAlgorithms] is the order in which, as a sender, it picks among
  /// the keys a recipient advertises.
  ///
  /// ⚠️ One atSign in one process holds one posture: every axis here is final
  /// at construction and [initAtClient] refuses a preference differing from
  /// the running client's, so two tests sharing an atSign share a posture.
  static AtClientPreference getPreference(String atsign,
      {required PqPosture posture,
      SigningAlgoType? authenticationKeyAlgorithm,
      Set<SigningAlgoType>? dataSigningKeyAlgorithms,
      List<String>? keyEstablishmentAlgorithms,
      List<String>? sealsToKeyAlgorithms,
      PqStartupGates? pqStartupGates}) {
    var preference = AtClientPreference(
        posture: posture,
        pqStartupGates: pqStartupGates,
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
  /// [posture], with its encryption keys loaded, and makes it the current
  /// client of the process-wide manager.
  ///
  /// The client opens on [atKeysIo], or on the demo atSign's credentials
  /// held in memory with none; a store handed in that holds no credential is
  /// given the demo atSign's, so a test keeps what the client files there
  /// and the client authenticates from the same store. A [preference] built
  /// at a different
  /// posture is refused rather than silently winning; [storage] is for a
  /// caller with no file-level bundle, such as a child isolate, where
  /// [isolateStorage]'s static is null.
  ///
  /// The same atSign already current is kept, with its preference reset;
  /// passing [atKeysIo] rebuilds it, since a client's key source is fixed at
  /// construction. Another atSign current is stopped first, as switching
  /// always has, and so is any client already running as the principal the
  /// keys name, since `open` refuses a second one.
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
    // The client reads its namespace off its preference, so a preference
    // built without one is given this call's before it reaches the client.
    preference.namespace ??= namespace;
    final manager = AtClientManager.getInstance();
    final loader = AtEncryptionKeysLoader.getInstance();

    final current = currentClientOf(manager);
    if (current != null &&
        current.getCurrentAtSign() == currentAtSign &&
        atKeysIo == null &&
        !current.isStopped) {
      AtClientImpl.refuseChangedRolloutAxes(
          running: current.getPreferences(),
          asked: preference,
          cacheKey:
              AtClientImpl.instanceKey(currentAtSign, current.enrollmentId));
      // Some other test may have messed with the preferences.
      current.setPreferences(preference);
      await loader.setEncryptionKeys(current, currentAtSign);
      return manager;
    }

    await current?.stop();
    final keys = atKeysIo ??
        InMemoryAtKeysIo.holding(
            currentAtSign, loader.createAtKeysFromDemoKeys(currentAtSign));
    await seedIfCredentialless(currentAtSign, keys);
    await stopClientRunningAs(currentAtSign, keys);
    final client = await Atsign(currentAtSign).open(
        keys: keys,
        preference: preference,
        namespace: namespace,
        storage: storage ?? storageFor(currentAtSign));
    manager.use(client);
    client.setPreferences(preference);
    // To setup encryption keys
    await loader.setEncryptionKeys(client, currentAtSign);
    return manager;
  }

  /// The manager's current client, or null while it holds none:
  /// `AtClientManager.atClient` throws rather than answering null.
  static AtClient? currentClientOf(AtClientManager manager) {
    try {
      return manager.atClient;
    } on StateError {
      return null;
    }
  }

  /// Files the demo atSign's credentials into [keys] when it holds none, or
  /// holds nothing at all: a test hands in a store of its own to keep what
  /// the client files there, and the client authenticates from that same
  /// store. Whatever the store already holds is kept.
  static Future<void> seedIfCredentialless(String atSign, AtKeysIo keys) async {
    if (keys is! WrittenAtKeysIo) return;
    final demo = AtEncryptionKeysLoader.getInstance().createAtKeysFromDemoKeys(
        atSign);
    final AtKeys held;
    try {
      held = await keys.read(atSign);
    } on Exception {
      await keys.write(atSign, demo);
      return;
    }
    // ignore: deprecated_member_use
    if (held.holdsAuthenticationMaterial &&
        held.defaultEncryptionPrivateKey != null) {
      return;
    }
    await keys.update(Atsign(atSign), (stored) {
      // ignore: deprecated_member_use
      stored.apkamPublicKey ??= demo.apkamPublicKey;
      // ignore: deprecated_member_use
      stored.apkamPrivateKey ??= demo.apkamPrivateKey;
      // ignore: deprecated_member_use
      stored.defaultEncryptionPublicKey ??= demo.defaultEncryptionPublicKey;
      // ignore: deprecated_member_use
      stored.defaultEncryptionPrivateKey ??= demo.defaultEncryptionPrivateKey;
      // ignore: deprecated_member_use
      stored.defaultSelfEncryptionKey ??= demo.defaultSelfEncryptionKey;
      return true;
    });
  }

  /// Stops any client of [atSign] running as the principal [keys] name, so a
  /// client opened on [keys] replaces it rather than being refused.
  static Future<void> stopClientRunningAs(String atSign, AtKeysIo keys) async {
    final principal = (await keys.read(atSign)).enrollmentToAuthenticateAs();
    for (final live in AtClientImpl.liveClientsFor(atSign)) {
      if (live.enrollmentId == principal) await live.stop();
    }
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
