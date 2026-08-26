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

  /// [posture], [authenticationKeyAlgorithm], [dataSigningKeyAlgorithms],
  /// [keyEstablishmentAlgorithms] and [sealsToKeyAlgorithms] must be threaded
  /// here because all five are final at construction — a test cannot set any
  /// of them on the returned instance.
  ///
  /// ⚠️ [keyEstablishmentAlgorithms] and [sealsToKeyAlgorithms] are different
  /// sides of the same exchange and are easy to confuse. The first is what
  /// this atSign MINTS and advertises; the second is the order in which, as a
  /// SENDER, it picks among the keys a recipient advertises. A test varying
  /// the wrong one changes nothing it can observe.
  /// Whatever `AtClientPreference` currently defaults its posture to.
  ///
  /// For the handful of tests whose SUBJECT is the default — "what does the
  /// SDK do when the app names nothing?" — and only those. A required
  /// parameter cannot express "the default", so pinning such a test to a
  /// named constant makes it stop following the thing it is about: it goes on
  /// passing while measuring a posture the SDK no longer ships. Every other
  /// test names the era it wants, so that a release moving the default cannot
  /// change what that test exercises.
  static PqPosture get sdkDefaultPosture => AtClientPreference().posture;

  /// [posture] has no default **on purpose**: what a posture decides is not
  /// cosmetic — whether this client mints signing keys, publishes an `_apsk`
  /// advertisement, seeds namespace keys and retrofits its own enrollment —
  /// and a test that has not chosen is a test whose subject is undeclared.
  /// Required so the compiler names every site, and so a new test cannot be
  /// written without choosing.
  ///
  /// ⚠️ **An approver or fixture client is `PqPosture.legacy`**, whatever the
  /// test is about. Seeding is the only posture-gated step in the whole PQ
  /// bootstrap, so an approver at `pqReady` or `pqActive` publishes
  /// `public:__nskey.<ns>@<atSign>` before any subject client does — and stays
  /// green while doing it. Classify by what the CLIENT does, not by what the
  /// file is called.
  ///
  /// ⚠️ **One atSign in one process holds one posture.** Every axis here is
  /// final at construction, and `setCurrentAtSign` refuses a preference that
  /// differs from the running client's — see
  /// `AtClientPreference.rolloutDifferencesFrom`. Two tests in a file that
  /// share an atSign therefore share a posture; give one its own atSign or its
  /// own enrollment to vary it.
  static AtClientPreference getPreference(String atsign,
      {required PqPosture posture,
      SigningAlgoType? authenticationKeyAlgorithm,
      Set<SigningAlgoType>? dataSigningKeyAlgorithms,
      List<String>? keyEstablishmentAlgorithms,
      List<String>? sealsToKeyAlgorithms}) {
    // One construction, not two. The constructor defaults every algorithm
    // field to the posture's own value (`?? posture.<field>`), so passing
    // nulls is indistinguishable from omitting them — the branch this used to
    // carry chose between two identical objects.
    var preference = AtClientPreference(
        posture: posture,
        authenticationKeyAlgorithm: authenticationKeyAlgorithm,
        dataSigningKeyAlgorithms: dataSigningKeyAlgorithms,
        keyEstablishmentAlgorithms: keyEstablishmentAlgorithms,
        sealsToKeyAlgorithms: sealsToKeyAlgorithms);
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
  /// [posture] is required even when [preference] is supplied, because the
  /// `??=` below applies [getPreference] inside this helper: a required
  /// parameter on that alone would leave every caller here naming nothing, and
  /// this is where most callers are. A supplied preference naming a different
  /// posture is refused rather than silently winning.
  static Future<AtClientManager> initAtClient(
      String currentAtSign, String namespace,
      {required PqPosture posture,
      AtClientPreference? preference,
      AtKeysIo? atKeysIo}) async {
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
