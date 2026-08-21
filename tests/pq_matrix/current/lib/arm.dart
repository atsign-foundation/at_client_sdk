// `AtChops` is deprecated in this tree's at_chops and is still the type
// 3.14.0's `setCurrentAtSign` takes. The shared `Attach` signature has to be
// one both arms can implement, so the deprecated spelling is the only one
// available to it — the same intersection constraint the scenario's
// `connect.dart` carries, for the same reason.
// ignore_for_file: deprecated_member_use

import 'package:at_auth/at_auth.dart'
    show AtAuth, AtAuthRequest, FileAtKeysIo;
import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_chops/at_chops.dart' show AtChops;
import 'package:at_client/at_client.dart'
    show AtClientManager, AtClientPreference, PqPosture;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart' show ClientSpec;

/// The stage-parameterised arm's preference.
///
/// The stage name becomes a [PqPosture], which is the whole difference between
/// this arm and the control one — 3.14.0 has no such type, so the published
/// arm's equivalent ignores its stage argument because it has nothing to map
/// it to.
///
/// ⚠️ **Only the two key axes are taken from the posture.** This matrix is
/// about which key signs an envelope and whether the peer can verify it, so
/// adopting a whole posture would also move the data path, the key exchange
/// and namespace seeding — none of which the exchange under test exercises,
/// and any of which could fail a cell for a reason that is not the signature.
/// The axes taken are the posture's own, so a cell still measures what the
/// stage means rather than a hand-picked pair.
AtClientPreference currentPreference(ClientSpec spec, String stage) =>
    AtClientPreference(
        authenticationKeyAlgorithm:
            _postureFor(stage).authenticationKeyAlgorithm,
        dataSigningKeyAlgorithms: _postureFor(stage).dataSigningKeyAlgorithms)
      ..hiveStoragePath = spec.storagePath
      ..commitLogPath = spec.storagePath
      ..rootDomain = spec.rootDomain
      ..rootPort = spec.rootPort
      ..namespace = spec.namespace
      ..decryptPackets = false
      ..tlsKeysSavePath = '${spec.storagePath}/tlsKeys'
      ..fetchOfflineNotifications = true;

/// Refuses an unknown stage rather than defaulting to [PqPosture.legacy].
///
/// A default here would make a typo in the driver read as a passing `legacy`
/// cell, which is the failure mode a matrix cannot survive: every stage would
/// still appear to run.
PqPosture _postureFor(String stage) => switch (stage) {
      'legacy' => PqPosture.legacy,
      'pqReady' => PqPosture.pqReady,
      'pqActive' => PqPosture.pqActive,
      _ => throw ArgumentError.value(
          stage, 'stage', 'not a posture - expected legacy|pqReady|pqActive'),
    };

/// Attaches as the stage's own enrollment, from the per-cell keyfile.
///
/// Each stage of the matrix is its own enrollment — the deployment model is
/// app = enrollment = unit, and four stages sharing one identity is what made
/// every stage client rewrite one shared `_apsk` record in turn. The keyfile
/// the driver copies in was written by the driver's enrolment of this stage,
/// so it holds the enrollment's APKAM keypair and conveyed encryption keys;
/// authenticating from it is the same restart path a production app walks.
///
/// The keyfile also keeps `SigningKeyMinting` live — an arm attached without
/// a key source would mint nothing, publish nothing, and pass every cell
/// while measuring an inert client. The keyfile is per-cell (the driver
/// copies a fresh one in), so a minted key does not leak into the next cell.
///
/// The demo [atChops] the shared scenario built is deliberately unused: this
/// client's identity is the enrollment's, and authenticating it with the
/// atSign's demo PKAM keys would make it `primary` — the shared identity the
/// per-stage enrollments exist to end. A current-arm cell spawned without an
/// enrollment id is refused for the same reason.
Future<AtClientManager> attachWithKeyfile(
    ClientSpec spec, AtClientPreference preference, AtChops atChops) async {
  final enrollmentId = spec.enrollmentId;
  if (enrollmentId == null) {
    throw ArgumentError(
        'the current arm authenticates as a stage enrollment and was spawned '
        'without --enrollment-id; a cell run as primary would write the '
        'shared _apsk record the per-stage enrollments exist to avoid');
  }
  final io = FileAtKeysIo(
      filePath: (atSign) => '${spec.storagePath}/$atSign.atKeys');
  final auth = AtAuth.create();
  final response = await auth.authenticate(AtAuthRequest(
    spec.atSign,
    rootDomain: AtRootDomain(spec.rootDomain, spec.rootPort),
    atKeysIo: io,
  ));
  if (response.isSuccessful != true) {
    throw StateError('authenticating as enrollment $enrollmentId failed: '
        '${response.atAuthKeys == null ? 'no keys' : 'auth refused'}');
  }
  return AtClientManager(spec.atSign).setCurrentAtSign(
      spec.atSign, spec.namespace, preference,
      atChops: auth.atChops,
      atKeysIo: io,
      enrollmentId: enrollmentId);
}
