import 'package:at_client/at_client.dart';
import 'package:at_end2end_test/config/config_util.dart';
import 'package:at_end2end_test/utils/test_constants.dart';

class TestPreferences {
  final atClientPreferencesMap = <String, AtClientPreference>{};

  /// The atSigns this pack shares with CI, and which are **never recycled**.
  ///
  /// `config14.yaml` and `config23.yaml` both name these four on
  /// root.atsign.wtf. Their keyfiles are repository secrets that a workflow
  /// run cannot rewrite, so anything a client mints or publishes on them
  /// outlives every run, and nothing in this project rotates it back out.
  ///
  /// A local run generates demo atSigns instead (`@alice🛠` and friends), so
  /// this set is empty of them on purpose: the guard below must not fire where
  /// the atServer is thrown away at the end of the run.
  static const Set<String> longLivedAtSigns = {
    '@ce2e1',
    '@ce2e2',
    '@ce2e3',
    '@ce2e4',
  };

  /// Refuses a preference that would write durable post-quantum state to one
  /// of [longLivedAtSigns].
  ///
  /// **Checked on the axes, never on the posture's identity.** Every one of
  /// these is independently overridable beside a posture, and a caller may
  /// build a posture of its own that none of the three constants names — so
  /// `posture == PqPosture.legacy` is a weaker test than it looks, and would
  /// pass a preference that retrofits.
  ///
  /// The three that write something that outlives the run:
  ///
  /// - [AtClientPreference.authenticationKeyAlgorithm] is what
  ///   `AtClientImpl.retrofitIsDue` compares against the algorithm the
  ///   enrollment holds. Anything stronger than `rsa2048` retrofits this
  ///   atSign's enrollment at the next start, mints a replacement and caps the
  ///   original — and there is **no preference opt-out**.
  /// - [AtClientPreference.seedNamespaceKeys] publishes
  ///   `public:__nskey.<ns>@<atSign>`, which every peer then seals to.
  /// - [AtClientPreference.dataSigningKeyAlgorithms] mints signing keys and
  ///   advertises them in `_apsk`.
  ///
  /// Called from [getPreference] and from `TestSuiteInitializer.testInitializer`,
  /// which between them are every route this pack has to a live client —
  /// including a preference a test built by hand and passed in.
  static void refuseDurableWritesToLongLivedAtSigns(
      String atSign, AtClientPreference preference) {
    if (!longLivedAtSigns.contains(atSign)) return;
    final reasons = <String>[
      if (preference.authenticationKeyAlgorithm != SigningAlgoType.rsa2048)
        'authenticationKeyAlgorithm is '
            '${preference.authenticationKeyAlgorithm.name}, so this client '
            'would RETROFIT the enrollment on $atSign at startup',
      if (preference.seedNamespaceKeys)
        'seedNamespaceKeys is true, so this client would publish a namespace '
            'key on $atSign that outlives the run',
      if (preference.dataSigningKeyAlgorithms.isNotEmpty)
        'dataSigningKeyAlgorithms is '
            '${preference.dataSigningKeyAlgorithms}, so this client would '
            'mint signing keys and advertise them on $atSign',
    ];
    if (reasons.isEmpty) return;
    throw StateError(
        '$atSign is one of this suite\'s long-lived atSigns, and this '
        'preference would write post-quantum state to it that no run takes '
        'back: ${reasons.join('; ')}. Those keyfiles are repository secrets a '
        'workflow cannot rewrite, and a retrofit CAPS the old enrollment '
        'rather than deleting it, so the damage would surface later and '
        'somewhere else. Use PqPosture.legacy here, and put the test that '
        'needs another era under test/pq/, which runs against a virtualenv '
        'the job throws away.');
  }

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
    refuseDurableWritesToLongLivedAtSigns(atSign, atClientPreference);
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
