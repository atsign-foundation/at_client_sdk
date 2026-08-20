import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysIo, AtKeysMaterial, CryptographicKeyType, KeyPartStatus;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart'
    show KeyEntryStatus;
import 'package:at_client/src/secret_sharing/key_package_registration.dart'
    show KeyPackageRegistration, PersistedApkamKeys, PersistedEncKey;
import 'package:at_commons/atsign.dart' show Atsign, AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('KeyPackagePersistence');

/// Backs [KeyPackageRegistration]'s enc keypair with the [AtKeys] this client
/// authenticates from, so a running client's key package is the one its
/// enrollment advertised.
///
/// Without this the mixin generates a fresh enc keypair on every
/// construction, which gives the client a different `kpid` each process. Since
/// a sender addresses an envelope to the kpid it read from the enrollment
/// record, a client whose kpid moves can never be sent anything it can find:
/// it scans for an address nobody writes to. The private half of the
/// advertised package is already in `AtKeys` — `enrollmentKeyPackageBuilder`
/// files both halves there under `keyId == kpid` at enrollment — so this
/// reunites the running client with material it has held all along.
///
/// Adoption only — nothing is written back. A keyfile with no key package
/// belongs to a client no sender can address anyway: a package is discovered
/// from the enrollment record, it rides `enroll:request`, and reaching the
/// record afterwards takes a deliberate `enroll:update`. Generating one and
/// filing it would mutate the user's keyfile at startup to produce an address
/// nobody can learn.
/// [enrollmentId] scopes the adoption to this client's own enrollment: a
/// retrofitted keyfile serves two principals, and each must adopt its OWN
/// package, never its co-tenant's — see [keyPackageMaterial].
@experimental
void bindKeyPackageToAtKeys(
  KeyPackageRegistration registration, {
  required AtKeysIo keysIo,
  required String atSign,
  String? enrollmentId,
}) {
  final Atsign owner = atSign.toAtsign();
  registration.loadApkamKeys ??= () => _load(keysIo, owner, enrollmentId);
}

/// The KEM enc seeds [atSign]'s keyfile holds for its key packages, or null
/// if it holds none.
///
/// A superseded package is adopted alongside the live one, as
/// [KeyEntryStatus.retired]. That is what lets a client restarting after a
/// rotation open envelopes a peer addressed before it — up to `envelopeTtl`,
/// seven days, of traffic that a client holding only its current key could not
/// even look for.
///
/// The status is the keyfile's own [KeyPartStatus], not a guess from age.
/// `AtKeys.retireKey` is how a rotation records the transition, and
/// `AtKeysAssurance` enforces at most one **active** `publicEncapsulation`
/// material per (enrollment, algorithm) — so the file already answers which
/// key is current, and inferring it from `createdAt` would be a second,
/// disagreeable opinion about a question the format settles.
Future<PersistedApkamKeys?> _load(
    AtKeysIo keysIo, Atsign atSign, String? enrollmentId) async {
  final AtKeys keys;
  try {
    keys = await keysIo.read(atSign);
  } catch (e) {
    _logger.info('No readable AtKeys for $atSign, so this client generates a '
        'key package rather than adopting one: $e');
    return null;
  }

  final materials = keyPackageMaterials(keys, enrollmentId: enrollmentId);
  if (materials.isEmpty) return null;
  final entries = <PersistedEncKey>[
    for (final material in materials)
      PersistedEncKey(
        encSeed: base64Encode(material.bytes.bytes),
        // Non-null by construction: keyPackageMaterials only returns material
        // whose algorithm token this build recognises.
        keyAlgo:
            SecretSharingAlgos.keyAlgoForMaterial(material.keyAlgorithmType)!,
        status: material.status == KeyPartStatus.active
            ? KeyEntryStatus.active
            : KeyEntryStatus.retired,
      ),
  ];
  final retired =
      entries.where((e) => e.status == KeyEntryStatus.retired).length;
  _logger.info('Adopted the ${entries.first.keyAlgo} key package $atSign '
      'already holds (kpid ${materials.first.keyId})'
      '${retired > 0 ? ', plus $retired superseded key(s) it can still be '
          'addressed at' : ''}');
  return PersistedApkamKeys(encKeys: entries);
}

/// The live private half of a key package in [keys], or null — the first entry
/// of [keyPackageMaterials], which is where the selection rule lives.
@experimental
AtKeysMaterial? keyPackageMaterial(AtKeys keys, {String? enrollmentId}) =>
    keyPackageMaterials(keys, enrollmentId: enrollmentId).firstOrNull;

/// Every usable private half of a key package in [keys] that belongs to one
/// enrollment, **active first, then retired, newest first within each**.
///
/// An nskey private is also filed as `privateDecapsulation`, so the part type
/// alone does not identify a key package — a client that had filed one would
/// otherwise adopt it as its recipient identity and lose the ability to open
/// anything addressed to it. What distinguishes the package is that both
/// halves are filed under one `keyId`: nskey privates arrive alone, their
/// public half being published on the atServer rather than kept here.
///
/// A list because rotating an enc key leaves the superseded one openable but no
/// longer advertised, and a client that dropped it on restart would strand
/// every envelope still in flight to it. 1:1:1 still says one enrollment
/// advertises one address at a time, which `AtKeysAssurance` enforces directly:
/// at most one **active** `publicEncapsulation` material per (enrollment,
/// algorithm). So the first entry is the live one rather than merely the newest.
///
/// [KeyPartStatus.dead] material is left out entirely. Retirement is as close
/// to deletion as a keyfile gets — status only ever moves forward, and dead is
/// the end of that road — so a dead key is not something to advertise to peers
/// or to keep answering on. Nothing in at_client marks one dead today; this
/// decides what happens when something does.
///
/// [enrollmentId] scopes the selection, and the tagged and untagged sets do not
/// mix: a retrofitted keyfile carries the legacy enrollment's package (untagged
/// — filed before materials carried enrollment ids) alongside the new
/// enrollment's (tagged with its id). A client takes its own tagged packages if
/// it has any, falls back to the untagged ones, and NEVER takes one tagged for
/// a different enrollment. Merging the two sets, or newest-wins across the
/// whole file, would hand a legacy client restarting on the shared keyfile the
/// PQ enrollment's kpid — an address its own enrollment record never
/// advertised.
@experimental
List<AtKeysMaterial> keyPackageMaterials(AtKeys keys, {String? enrollmentId}) {
  // Any key-establishment algorithm this build implements, not X-Wing alone:
  // an atSign configured for ML-KEM-1024 files its package under that token,
  // and an X-Wing-only filter would make it invisible — the client would then
  // mint a fresh key and answer at a kpid its enrollment never advertised, so
  // nothing addressed to it could ever arrive.
  bool isKeyEstablishment(AtKeysMaterial m) =>
      SecretSharingAlgos.keyAlgoForMaterial(m.keyAlgorithmType) != null;

  // Paired by `(owner, keyId)`, not by keyId alone. A keyId is unique within
  // its enrollment and not across the document, so a keyId-only set would let
  // one enrollment's published address vouch for another enrollment's private
  // half — and this function's whole job is to never hand a client a key its
  // own enrollment record never advertised.
  final publicIds = {
    for (final m in keys.keys)
      if (m.keyPartType == CryptographicKeyType.publicEncapsulation &&
          isKeyEstablishment(m))
        (m.enrollmentId, m.keyId)
  };
  final candidates = keys.keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateDecapsulation &&
          isKeyEstablishment(m) &&
          m.status != KeyPartStatus.dead &&
          publicIds.contains((m.enrollmentId, m.keyId)) &&
          (m.enrollmentId == null || m.enrollmentId == enrollmentId))
      .toList()
    ..sort((a, b) {
      if ((a.status == KeyPartStatus.active) !=
          (b.status == KeyPartStatus.active)) {
        return a.status == KeyPartStatus.active ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
  if (enrollmentId != null) {
    final own =
        candidates.where((m) => m.enrollmentId == enrollmentId).toList();
    if (own.isNotEmpty) return own;
  }
  return candidates.where((m) => m.enrollmentId == null).toList();
}
