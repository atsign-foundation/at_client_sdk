// `AtChops` is deprecated in this tree's at_chops and is still the type
// 3.14.0's `setCurrentAtSign` takes. The shared `Attach` signature has to be
// one both arms can implement, so the deprecated spelling is the only one
// available to it — the same intersection constraint the scenario's
// `connect.dart` carries, for the same reason.
// ignore_for_file: deprecated_member_use

import 'package:at_auth/at_auth.dart' show FileAtKeysIo;
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

/// Attaches with a key source, which the control arm structurally cannot do.
///
/// This is the difference that matters at `pqActive`. `SigningKeyMinting` is
/// inert for a client whose `atKeysIo` is null, and inert again for one whose
/// `AtKeysIo` cannot persist — so an arm attached without one would mint
/// nothing, publish nothing, and pass every cell while measuring an inert
/// client. The keyfile is per-cell (the driver copies a fresh one in), so a
/// minted key does not leak into the next cell.
Future<AtClientManager> attachWithKeyfile(
        ClientSpec spec, AtClientPreference preference, AtChops atChops) =>
    AtClientManager(spec.atSign).setCurrentAtSign(
        spec.atSign, spec.namespace, preference,
        atChops: atChops,
        atKeysIo: FileAtKeysIo(
            filePath: (atSign) => '${spec.storagePath}/$atSign.atKeys'));
