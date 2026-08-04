import 'dart:convert' show base64Encode;

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysIo, AtKeysMaterial, CryptographicKeyType, KeyAlgorithmType;
import 'package:at_client/src/secret_sharing/key_package_registration.dart'
    show KeyPackageRegistration, PersistedApkamKeys;
import 'package:at_commons/atsign.dart' show Atsign, AtsignString;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

final _logger = AtSignLogger('KeyPackagePersistence');

/// Backs [KeyPackageRegistration]'s enc keypair with the [AtKeys] this client
/// authenticates from, so a running client's key package is the one its
/// enrollment advertised.
///
/// Without this the mixin generates a fresh X-Wing keypair on every
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
/// from the enrollment record, it rides `enroll:request`, and there is no
/// post-enrollment write path. Generating one and filing it would mutate the
/// user's keyfile at startup to produce an address nobody can learn.
@experimental
void bindKeyPackageToAtKeys(
  KeyPackageRegistration registration, {
  required AtKeysIo keysIo,
  required String atSign,
}) {
  final Atsign owner = atSign.toAtsign();
  registration.loadApkamKeys ??= () => _load(keysIo, owner);
}

/// The X-Wing enc seed [atSign]'s keyfile holds for its key package, or null
/// if it holds none.
Future<PersistedApkamKeys?> _load(AtKeysIo keysIo, Atsign atSign) async {
  final AtKeys keys;
  try {
    keys = await keysIo.read(atSign);
  } catch (e) {
    _logger.info('No readable AtKeys for $atSign, so this client generates a '
        'key package rather than adopting one: $e');
    return null;
  }

  final material = keyPackageMaterial(keys);
  if (material == null) return null;
  _logger.info('Adopted the key package $atSign already holds '
      '(kpid ${material.keyId})');
  return PersistedApkamKeys(xWingSeed: base64Encode(material.bytes.bytes));
}

/// The private half of the key package in [keys], or null.
///
/// An nskey private is also an X-Wing `privateDecapsulation`, so the part type
/// alone does not identify a key package — a client that had filed one would
/// otherwise adopt it as its recipient identity and lose the ability to open
/// anything addressed to it. What distinguishes the package is that both
/// halves are filed under one `keyId`: nskey privates arrive alone, their
/// public half being published on the atServer rather than kept here.
///
/// The newest wins if a keyfile somehow carries more than one. 1:1:1 says
/// there is exactly one, and picking deterministically is what keeps a client
/// that violates it from changing identity between restarts.
@experimental
AtKeysMaterial? keyPackageMaterial(AtKeys keys) {
  final publicIds = {
    for (final m in keys.keys)
      if (m.keyPartType == CryptographicKeyType.publicEncapsulation &&
          m.keyAlgorithmType == KeyAlgorithmType.xWing)
        m.keyId
  };
  final candidates = keys.keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateDecapsulation &&
          m.keyAlgorithmType == KeyAlgorithmType.xWing &&
          publicIds.contains(m.keyId))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return candidates.firstOrNull;
}
