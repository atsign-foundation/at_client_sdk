import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/utils/test_constants.dart';

class TestPreferences {
  final atClientPreferencesMap = <String, AtClientPreference>{};

  static final TestPreferences _singleton = TestPreferences._internal();

  TestPreferences._internal();

  factory TestPreferences.getInstance() {
    return _singleton;
  }

  /// The preference for [atSign], built on the first ask and reused after.
  ///
  /// [posture] has no default **on purpose**: every test in this pack states
  /// the era its client runs at, so the compiler names any site that has not
  /// chosen and a new test cannot be written without choosing. What a posture
  /// changes is not cosmetic — it decides whether this client mints signing
  /// keys, publishes an `_apsk` advertisement, seeds namespace keys and
  /// retrofits its own enrollment.
  ///
  /// ⛔ **The atSigns this pack runs against are never recycled.** `@ce2e1`
  /// through `@ce2e4` are long-lived, and their keyfiles are repository
  /// secrets a workflow run cannot rewrite. Anything a posture causes this
  /// client to mint or publish therefore stays on them permanently, and a
  /// retrofit **caps** the legacy enrollment rather than deleting it — so a
  /// mis-chosen posture arms a delayed, silent break rather than failing now.
  /// Pin them to [PqPosture.legacy] unless the test is about the
  /// post-quantum behaviour itself.
  ///
  /// A second ask naming a different posture is **refused**. The memo is per
  /// atSign, so without the refusal this parameter would be decorative for
  /// every atSign the pack uses twice — which is most of them — and a test
  /// would run at whichever posture its file happened to ask for first.
  AtClientPreference getPreference(String atSign,
      {required PqPosture posture}) {
    final existing = atClientPreferencesMap[atSign];
    if (existing != null) {
      if (existing.posture != posture) {
        throw StateError(
            '$atSign already has a preference built at '
            '${_describe(existing.posture)}, and this asks for '
            '${_describe(posture)}. AtClientPreference.posture is final, so '
            'the two cannot be reconciled, and every test in this process '
            'naming $atSign shares one client. Agree on a posture, or give '
            'one of them an atSign of its own.');
      }
      return existing;
    }
    // `posture` is final on AtClientPreference, so it is a constructor
    // argument rather than one of the assignments below.
    var atClientPreference = AtClientPreference(posture: posture);
    atClientPreference.hiveStoragePath = 'test/hive/client';
    atClientPreference.commitLogPath = 'test/hive/client/commit';
    atClientPreference.rootDomain = ConfigUtil.getYaml()['root_server']['url'];
    // Optional `root_server.port` (e.g. a base-port virtualenv run); defaults
    // to the standard root port 64 when absent.
    atClientPreference.rootPort =
        ConfigUtil.getYaml()['root_server']['port'] ?? 64;
    atClientPreference.syncRegex = TestConstants.namespace;
    atClientPreferencesMap[atSign] = atClientPreference;
    return atClientPreference;
  }
}

/// A posture's name, for a refusal message.
///
/// `PqPosture` carries none: it is a set of axes, and an app may build one the
/// three constants do not name.
String _describe(PqPosture posture) {
  if (posture == PqPosture.legacy) return 'PqPosture.legacy';
  if (posture == PqPosture.pqReady) return 'PqPosture.pqReady';
  if (posture == PqPosture.pqActive) return 'PqPosture.pqActive';
  return 'a posture none of the three constants names';
}
