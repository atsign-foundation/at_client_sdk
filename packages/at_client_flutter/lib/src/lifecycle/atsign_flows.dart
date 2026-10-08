import 'package:at_client/at_client.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:path_provider/path_provider.dart';

/// The storage a client this package opens for [atSign] uses: [storage] when
/// the app passed one; else a Hive store, closed by the client when it stops,
/// under the preference's `hiveStoragePath` while the app sets it, or under
/// the app's support directory, the one at_client_mobile's examples gave
/// `hiveStoragePath`, so an app that followed them finds its store.
///
/// Null when [preference] asks for no local store and none was passed, which
/// at_client accepts only without storage.
Future<AtClientStorage?> storageOrDefault(
  String atSign,
  AtClientPreference preference,
  AtClientStorage? storage,
) async {
  if (storage != null || !preference.isLocalStoreRequired) return storage;
  final path =
      // ignore: deprecated_member_use
      preference.hiveStoragePath ??
      (await getApplicationSupportDirectory()).path;
  return HiveAtClientStorage(
    atSign: AtUtils.fixAtSign(atSign),
    storagePath: path,
    closedByClient: true,
  );
}

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
    AtLookUpFactory? lookUps,
    void Function(ProgressEvent event)? onProgress,
  }) async => Atsign(atSign).activate(
    cramSecret: cramSecret,
    keys: keys,
    preference: preference,
    storage: await storageOrDefault(atSign, preference, storage),
    lookUps: lookUps,
    onProgress: onProgress,
  );

  Future<AtClient> open(
    String atSign, {
    required AtKeysIo keys,
    required AtClientPreference preference,
    AtClientStorage? storage,
    AtLookUpFactory? lookUps,
  }) async => Atsign(atSign).open(
    keys: keys,
    preference: preference,
    storage: await storageOrDefault(atSign, preference, storage),
    lookUps: lookUps,
  );

  Future<PendingEnrollment?> resumeEnrollment(
    String atSign, {
    required String app,
    required String device,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    AtLookUpFactory? lookUps,
  }) => Atsign(atSign).resumeEnrollment(
    app: app,
    device: device,
    keys: keys,
    preference: preference,
    lookUps: lookUps,
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
    AtLookUpFactory? lookUps,
  }) => Atsign(atSign).enroll(
    otp: otp,
    app: app,
    device: device,
    namespaces: namespaces,
    keys: keys,
    preference: preference,
    signingAlgo: signingAlgo,
    keyExchangeMode: keyExchangeMode,
    lookUps: lookUps,
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
