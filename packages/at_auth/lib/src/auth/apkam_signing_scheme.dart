import 'dart:typed_data';

import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_auth/src/keys/at_keys.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_auth/src/keys/serialization/key_ids.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// Builds the [AtLookUp] an authentication runs over.
///
/// Injected at `AtAuth.create` / `AtEnrollment.create` time to take over
/// construction; when none is injected the default is
/// [ApkamSigningScheme.lookUpFactory].
///
/// [keys] is null for the CRAM-only connection an activation starts on, before
/// any key material exists.
///
/// The connection returned belongs to whoever called the factory: at_auth closes
/// it when the operation that asked for it fails or finishes with it. Do not
/// hand back a connection the caller still needs.
typedef AtLookUpFactory = AtLookUp Function(
  Atsign atsign,
  AtRootDomain rootDomain,
  AtKeys? keys, {
  String? enrollmentId,
});

/// The APKAM signing scheme authentication uses, chosen by the caller at
/// `AtAuth.create` / `AtEnrollment.create` time.
///
/// It is deliberately **not** inferred from the key material. A keyset minted by
/// [AtKeys.generate] carries both a classical and a post-quantum APKAM key, so
/// key material cannot express which one an atServer expects — that is a
/// property of the deployment, and the application (at_client) owns it.
enum ApkamSigningScheme {
  /// RSA-2048/SHA-256, signed with the legacy `apkamPrivateKey`. What every
  /// atServer verifies today.
  legacy,

  /// ML-DSA-65 (FIPS 204), signed with the [KeyIds.apkamPQ] private material.
  /// Hashing is intrinsic to the scheme, so no separate hashing algorithm is
  /// declared on the wire.
  postQuantum;

  /// The [AtLookUpFactory] used when a caller injects none — every connection
  /// built signs with this scheme and the matching key from the keys it is
  /// given.
  AtLookUpFactory get lookUpFactory =>
      (atsign, rootDomain, keys, {enrollmentId}) => buildAtLookUp(
            this,
            atsign,
            rootDomain,
            keys,
            enrollmentId: enrollmentId,
          );
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
  ApkamSigningScheme signing,
  Atsign atsign,
  AtRootDomain rootDomain,
  AtKeys? keys, {
  String? enrollmentId,
}) {
  final pkamPrivateKey = keys == null ? null : _pkamPrivateKey(signing, keys);

  return switch (signing) {
    ApkamSigningScheme.legacy => AtLookUp.legacy(
        atsign,
        rootDomain.rootDomain,
        rootDomain.rootPort,
        pkamPrivateKey: pkamPrivateKey,
        enrollmentId: enrollmentId,
      ),
    ApkamSigningScheme.postQuantum => AtLookUp.pq(
        atsign,
        rootDomain.rootDomain,
        rootDomain.rootPort,
        pkamPrivateKey: pkamPrivateKey,
        enrollmentId: enrollmentId,
      ),
  };
}

Uint8List _pkamPrivateKey(ApkamSigningScheme signing, AtKeys keys) {
  final key = switch (signing) {
    // ignore: deprecated_member_use_from_same_package
    ApkamSigningScheme.legacy => keys.apkamPrivateKey?.bytes,
    ApkamSigningScheme.postQuantum =>
      keys.getKey(KeyIds.apkamPQ, CryptographicKeyType.privateSigning)?.bytes,
  };
  if (key == null) {
    throw AtAuthenticationException(
        'The keys for ${keys.atsign} carry no ${signing.name} APKAM private '
        'key to authenticate with');
  }
  return key;
}
