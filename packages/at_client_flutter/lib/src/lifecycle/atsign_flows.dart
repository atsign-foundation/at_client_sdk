import 'package:at_client/at_client_io.dart';
import 'package:at_client/hive.dart';
import 'package:at_utils/at_progress.dart';
import 'package:at_utils/at_utils.dart';
import 'package:path_provider/path_provider.dart';

/// The storage a client this package opens for [atSign] uses: [storage] when
/// the app passed one; else a Hive store, closed by the client when it stops,
/// under the preference's `hiveStoragePath` while the app sets it, or under
/// the app's support directory, the one at_client_mobile's examples gave
/// `hiveStoragePath`, so an app that followed them finds its store.
///
/// A verb that takes `storage:` and is not on [AtsignFlows], such as
/// `PendingEnrollment.client`, takes it from here.
Future<AtClientStorage> storageOrDefault(
  String atSign,
  AtClientPreference preference, [
  AtClientStorage? storage,
]) async {
  if (storage != null) return storage;
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

/// The `Atsign` lifecycle verbs with this package's platform defaults, for an
/// app with its own UI: the store is [storageOrDefault]'s unless the app
/// passes `storage`, each connection goes over TLS on TCP unless it passes
/// `lookUps`, and the atServer is the one the atDirectory the preference
/// names gives for the atSign.
///
/// The dialogs run their verbs through one, given as their `flows`, so a
/// widget test can stand in for the verbs, which as extension methods on
/// `Atsign` no mock can intercept.
class AtsignFlows {
  const AtsignFlows();

  /// `Atsign.activate`: activates [atSign] with its [cramSecret], filing its
  /// first keys in [keys], and hands back the client opened on them.
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
    lookUps: lookUps ?? secureSocketLookUps(),
    secondaryAddressFinder: _atDirectoryOf(preference),
    onProgress: onProgress,
  );

  /// `Atsign.open`: opens a client for [atSign] on the keys in [keys].
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
    lookUps: lookUps ?? secureSocketLookUps(),
    secondaryAddressFinder: _atDirectoryOf(preference),
  );

  /// `Atsign.resumeEnrollment`: the request for [app] and [device] already
  /// filed in [keys] and awaiting approval, or null when there is none.
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
    lookUps: lookUps ?? secureSocketLookUps(),
    secondaryAddressFinder: _atDirectoryOf(preference),
  );

  /// `Atsign.enroll`: asks [atSign]'s atServer, with [otp], to enroll this
  /// device for [namespaces], filing the request's keys in [keys]; the
  /// returned enrollment's `client` opens once it is approved.
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
    lookUps: lookUps ?? secureSocketLookUps(),
    secondaryAddressFinder: _atDirectoryOf(preference),
  );

  SecondaryAddressFinder _atDirectoryOf(AtClientPreference preference) =>
      CacheableSecondaryAddressFinder(
        preference.rootDomain,
        preference.rootPort,
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
