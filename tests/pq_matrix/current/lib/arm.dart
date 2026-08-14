// `AtChops` is deprecated in this tree's at_chops and is still the type
// 3.14.0's `setCurrentAtSign` takes. The shared `Attach` signature has to be
// one both arms can implement, so the deprecated spelling is the only one
// available to it — the same intersection constraint the scenario's
// `connect.dart` carries, for the same reason.
// ignore_for_file: deprecated_member_use

import 'package:at_auth/at_auth.dart' show FileAtKeysIo;
import 'package:at_chops/at_chops.dart' show AtChops;
import 'package:at_client/at_client.dart'
    show AtClientManager, AtClientPreference, SigningRollout;
import 'package:pq_matrix_scenario/pq_matrix_scenario.dart' show ClientSpec;

/// The stage-parameterised arm's preference.
///
/// The stage name becomes a [SigningRollout], which is the whole difference
/// between this arm and the control one — 3.14.0 has no such type, so the
/// published arm's equivalent ignores its stage argument because it has
/// nothing to map it to.
///
/// `inUseSigningAlgorithms` is deliberately **not** set beside it. It is
/// derived from the stage, and setting both would be two controls over one
/// behaviour with no way to tell which was lying on the day they disagreed.
AtClientPreference currentPreference(ClientSpec spec, String stage) =>
    AtClientPreference(signingRollout: _rolloutFor(stage))
      ..hiveStoragePath = spec.storagePath
      ..commitLogPath = spec.storagePath
      ..rootDomain = spec.rootDomain
      ..rootPort = spec.rootPort
      ..namespace = spec.namespace
      ..decryptPackets = false
      ..tlsKeysSavePath = '${spec.storagePath}/tlsKeys'
      ..fetchOfflineNotifications = true;

/// Refuses an unknown stage rather than defaulting to [SigningRollout.now].
///
/// A default here would make a typo in the driver read as a passing `now`
/// cell, which is the failure mode a matrix cannot survive: every stage would
/// still appear to run.
SigningRollout _rolloutFor(String stage) => SigningRollout.values
    .firstWhere((r) => r.name == stage,
        orElse: () => throw ArgumentError.value(stage, 'stage',
            'not a SigningRollout — expected ${SigningRollout.values.map((r) => r.name).join('|')}'));

/// Attaches with a key source, which the control arm structurally cannot do.
///
/// This is the difference that matters at rollout 2. `SigningKeyMinting` is
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
