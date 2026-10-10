import 'dart:async' show FutureOr;

import 'package:meta/meta.dart' show experimental;

/// Whether the content key for a destination and namespace should be replaced
/// before anything else is written under it.
///
/// Asked on the write path, so a policy that awaits makes every encrypting
/// write wait for it. Returning true cuts a fresh content key and conveys it;
/// the superseded conveyance record is retained, so an enrollment that joins
/// later can still read what was written before it.
@experimental
typedef CkRotationPolicy = FutureOr<bool> Function(CkRotationContext ck);

/// What a [CkRotationPolicy] is told about the content key it is deciding on.
///
/// A content key is scoped to the destination and the namespace together: the
/// same namespace toward two atSigns is two keys.
@experimental
class CkRotationContext {
  const CkRotationContext({
    required this.destination,
    required this.namespace,
    required this.ckKid,
    required this.cutAt,
    required this.now,
  });

  /// The atSign whose namespace key this content key is sealed to.
  final String destination;

  /// The namespace level the destination's nskey resolved at, which is the
  /// scope the content key protects — not necessarily the namespace of the
  /// record being written, since resolution walks up.
  final String namespace;

  final String ckKid;

  /// When this content key was cut.
  ///
  /// The conveyance record's own `createdAt` where this client read it back,
  /// and this device's clock where this client cut it, so two devices can
  /// disagree by their clock skew.
  final DateTime cutAt;

  /// Passed in rather than read, so a policy is testable without a clock.
  final DateTime now;

  /// How long ago this content key was cut.
  Duration get age => now.difference(cutAt);
}

/// The default [CkRotationPolicy]: replace a content key once it is a year
/// old.
///
/// Each value is encrypted under its own key, derived from the content key and
/// a fresh salt, so no usage limit bounds how long a content key can serve, and
/// a revocation replaces it on its own cause. A year is NIST SP 800-57 Part 1's
/// suggested cryptoperiod for a key-derivation key, which is what a content
/// key is.
@experimental
bool rotateCkAfterOneYear(CkRotationContext ck) =>
    ck.age >= const Duration(days: 365);

/// A [CkRotationPolicy] that replaces a content key once it is a week old.
@experimental
bool rotateCkAfterOneWeek(CkRotationContext ck) =>
    ck.age >= const Duration(days: 7);

/// Whether the namespace key should be replaced before it is used again.
///
/// Asked before a content key is conveyed, but only where the destination is
/// this client's own atSign, and once per authorised namespace at every client
/// start. Returning true mints fresh material, retains the previous private so
/// records sealed to it still open, and conveys the new private to every
/// authorised enrollment.
@experimental
typedef NskeyRotationPolicy = FutureOr<bool> Function(NskeyRotationContext ns);

/// What an [NskeyRotationPolicy] is told about the namespace key it is
/// deciding on.
@experimental
class NskeyRotationContext {
  const NskeyRotationContext({
    required this.namespace,
    required this.nskeyKid,
    required this.createdAt,
    required this.now,
  });

  final String namespace;

  /// The advertised generation's own id.
  final String nskeyKid;

  /// When the generation was minted, as its own advertisement states it.
  final DateTime createdAt;

  /// Passed in rather than read, so a policy is testable without a clock.
  final DateTime now;

  /// How long ago the generation was minted.
  Duration get age => now.difference(createdAt);
}

/// The default [NskeyRotationPolicy]: replace a namespace key once its
/// advertisement says it was minted a year ago.
///
/// A revocation rotates the namespace keys the revoked enrollment held on its
/// own cause; this is what heals a compromise nobody detected. A year sits in
/// NIST SP 800-57 Part 1's 1-to-2-year range for a public key-transport key.
@experimental
bool rotateNskeyAfterOneYear(NskeyRotationContext ns) =>
    ns.age >= const Duration(days: 365);

/// An [NskeyRotationPolicy] that never replaces a namespace key on its own,
/// leaving rotation to revocation and to the application.
@experimental
bool neverRotateNskey(NskeyRotationContext ns) => false;
