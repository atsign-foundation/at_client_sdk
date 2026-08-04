import 'dart:typed_data';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/key_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// The APKAM signing scheme authentication uses, chosen by the caller at
/// `AtAuth.create` / `AtEnrollment.create` time.
///
/// It is deliberately **not** inferred from the key material. A keyset minted by
/// [AtKeys.generate] carries both a classical and a post-quantum APKAM key, so
/// key material cannot express which one an atServer expects — that is a
/// property of the deployment, and the application (at_client) owns it.
enum ApkamSigning {
  /// RSA-2048/SHA-256, signed with the legacy `apkamPrivateKey`. What every
  /// atServer verifies today.
  legacy,

  /// ML-DSA-65 (FIPS 204), signed with the [KeyIds.apkamPQ] private material.
  /// Hashing is intrinsic to the scheme, so no separate hashing algorithm is
  /// declared on the wire.
  postQuantum,
}

/// Builds the [AtLookUp] an authentication runs over, signing with [signing]
/// and the matching key from [keys].
///
/// at_lookup binds its PKAM key and signing algorithm at construction and keeps
/// them immutable, so the connection cannot be built until the keys are in
/// hand. That is why authentication owns this step: it reads (or mints) the keys
/// first, then builds the connection that can sign with them.
///
/// [keys] is null for the CRAM-only connection an activation starts on, before
/// any key material exists.
///
/// Throws [AtAuthenticationException] when [keys] carries no APKAM private key
/// for [signing] — a keyset that cannot authenticate the way it was asked to.
AtLookUp buildAtLookUp(
  ApkamSigning signing,
  Atsign atsign,
  AtRootDomain rootDomain,
  AtKeys? keys, {
  String? enrollmentId,
}) {
  final pkamPrivateKey = keys == null ? null : _pkamPrivateKey(signing, keys);

  return switch (signing) {
    ApkamSigning.legacy => AtLookUp.legacy(
        atsign,
        rootDomain.rootDomain,
        rootDomain.rootPort,
        pkamPrivateKey: pkamPrivateKey,
        enrollmentId: enrollmentId,
      ),
    ApkamSigning.postQuantum => AtLookUp.pq(
        atsign,
        rootDomain.rootDomain,
        rootDomain.rootPort,
        pkamPrivateKey: pkamPrivateKey,
        enrollmentId: enrollmentId,
      ),
  };
}

Uint8List _pkamPrivateKey(ApkamSigning signing, AtKeys keys) {
  final key = switch (signing) {
    // ignore: deprecated_member_use_from_same_package
    ApkamSigning.legacy => keys.apkamPrivateKey?.bytes,
    ApkamSigning.postQuantum =>
      keys.getKey(KeyIds.apkamPQ, CryptographicKeyType.privateSigning)?.bytes,
  };
  if (key == null) {
    throw AtAuthenticationException(
        'The keys for ${keys.atsign} carry no ${signing.name} APKAM private '
        'key to authenticate with');
  }
  return key;
}
