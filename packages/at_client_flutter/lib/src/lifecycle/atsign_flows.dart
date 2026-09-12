import 'package:at_client/at_client.dart';
import 'package:at_utils/at_progress.dart';

/// The atSign an app chose to work with, and the atDirectory it lives under.
class AtsignSelection {
  final String atSign;
  final AtRootDomain rootDomain;

  const AtsignSelection(this.atSign, this.rootDomain);

  @override
  String toString() =>
      '$atSign at ${rootDomain.rootDomain}:'
      '${rootDomain.rootPort}';
}

/// The lifecycle verbs the dialogs run, as one object a test can stand in
/// for: the verbs themselves are extension methods on `Atsign`, which no
/// mock can intercept.
class AtsignFlows {
  const AtsignFlows();

  Future<AtClient> activate(
    String atSign, {
    required String cramSecret,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    AtClientStorage? storage,
    void Function(ProgressEvent event)? onProgress,
  }) => Atsign(atSign).activate(
    cramSecret: cramSecret,
    keys: keys,
    preference: preference,
    storage: storage,
    onProgress: onProgress,
  );

  Future<AtClient> open(
    String atSign, {
    required AtKeysIo keys,
    required AtClientPreference preference,
    AtClientStorage? storage,
  }) =>
      Atsign(atSign).open(keys: keys, preference: preference, storage: storage);

  Future<PendingEnrollment?> resumeEnrollment(
    String atSign, {
    required String app,
    required String device,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
  }) => Atsign(atSign).resumeEnrollment(
    app: app,
    device: device,
    keys: keys,
    preference: preference,
  );

  Future<PendingEnrollment> enroll(
    String atSign, {
    required String otp,
    required String app,
    required String device,
    required Map<String, String> namespaces,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    SigningAlgoType? signingAlgo,
    EnrollmentKeyExchangeMode? keyExchangeMode,
  }) => Atsign(atSign).enroll(
    otp: otp,
    app: app,
    device: device,
    namespaces: namespaces,
    keys: keys,
    preference: preference,
    signingAlgo: signingAlgo,
    keyExchangeMode: keyExchangeMode,
  );
}

/// [preference] with [rootDomain] stamped on it, so a client opened under it
/// looks the atSign up where the app said.
AtClientPreference under(
  AtClientPreference preference,
  AtRootDomain? rootDomain,
) {
  if (rootDomain != null) {
    preference
      ..rootDomain = rootDomain.rootDomain
      ..rootPort = rootDomain.rootPort;
  }
  return preference;
}
