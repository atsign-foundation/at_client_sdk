import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart'
    show
        AtKeys,
        AtKeysIo,
        CryptographicMaterial,
        CryptographicMaterialRole,
        CryptographicMaterialStatus;
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
/// Adoption only — nothing is written back.
///
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
/// A superseded package is adopted alongside the live one, carrying whatever
/// status the keyfile gives it, so a client restarting after a rotation can
/// still open envelopes a peer addressed before it.
///
/// The status token crosses **verbatim**, and it is the keyfile's own
/// [CryptographicMaterialStatus] rather than a guess from age. Only
/// [KeyEntryStatus.active] is offered for new traffic, so an unknown token is
/// never the advertised address.
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
        // NOTE: non-null by construction — keyPackageMaterials only returns
        // material whose algorithm token this build recognises.
        keyAlgo: SecretSharingAlgos.keyAlgoForMaterial(material.algorithm)!,
        // NOTE: the keyfile's own token, carried across rather than collapsed
        // to one of the two this build knows — flattening a newer client's
        // third value to `retired` would say less about the key than its own
        // keyfile does.
        status: KeyEntryStatus.of(material.status),
      ),
  ];
  final retained = entries.where((e) => !e.offeredForNewOperations).toList();
  _logger.info('Adopted the ${entries.first.keyAlgo} key package $atSign '
      'already holds (kpid ${materials.first.keyId})'
      '${retained.isEmpty ? '' : ', plus ${retained.length} retained key(s) it '
          'can still open envelopes with '
          '(${retained.map((e) => e.status).join(', ')})'}');
  return PersistedApkamKeys(encKeys: entries);
}

/// The live private half of a key package in [keys], or null — the first entry
/// of [keyPackageMaterials], which is where the selection rule lives.
@experimental
CryptographicMaterial? keyPackageMaterial(AtKeys keys,
        {String? enrollmentId}) =>
    keyPackageMaterials(keys, enrollmentId: enrollmentId).firstOrNull;

/// Every usable private half of a key package in [keys] that belongs to one
/// enrollment, **active first, then retired, newest first within each**.
///
/// An nskey private is also filed as `privateDecapsulation`, so the part type
/// alone does not identify a key package. What distinguishes the package is
/// that both halves are filed under one `keyId`: nskey privates arrive alone,
/// their public half being published on the atServer rather than kept here.
///
/// A list because rotating an enc key leaves the superseded one openable but no
/// longer advertised, and a client that dropped it on restart would strand
/// every envelope still in flight to it. The first entry is the live one rather
/// than merely the newest: at most one **active** `publicEncapsulation`
/// material exists per (enrollment, algorithm).
///
/// [CryptographicMaterialStatus.dead] material is left out entirely — a dead
/// key is not something to advertise to peers or to keep answering on.
///
/// [enrollmentId] scopes the selection, and the tagged and untagged sets do not
/// mix: a retrofitted keyfile carries an untagged package alongside a tagged
/// one. A client takes its own tagged packages if it has any, falls back to the
/// untagged ones, and NEVER takes one tagged for a different enrollment.
/// Merging the two sets, or newest-wins across the whole file, would hand a
/// client restarting on a shared keyfile an address its own enrollment record
/// never advertised.
@experimental
List<CryptographicMaterial> keyPackageMaterials(AtKeys keys,
    {String? enrollmentId}) {
  bool isKeyEstablishment(CryptographicMaterial m) =>
      SecretSharingAlgos.keyAlgoForMaterial(m.algorithm) != null;

  // NOTE: paired by `(owner, keyId)`, not by keyId alone — a keyId is unique
  // within its enrollment and not across the document, so a keyId-only set
  // would let one enrollment's published address vouch for another
  // enrollment's private half.
  final publicIds = {
    for (final m in keys.keys)
      if (m.role == CryptographicMaterialRole.publicEncapsulation &&
          isKeyEstablishment(m))
        (m.enrollmentId, m.keyId)
  };
  final candidates = keys.keys
      .where((m) =>
          m.role == CryptographicMaterialRole.privateDecapsulation &&
          isKeyEstablishment(m) &&
          m.status != CryptographicMaterialStatus.dead &&
          publicIds.contains((m.enrollmentId, m.keyId)) &&
          (m.enrollmentId == null || m.enrollmentId == enrollmentId))
      .toList()
    ..sort((a, b) {
      if ((a.status == CryptographicMaterialStatus.active) !=
          (b.status == CryptographicMaterialStatus.active)) {
        return a.status == CryptographicMaterialStatus.active ? -1 : 1;
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
