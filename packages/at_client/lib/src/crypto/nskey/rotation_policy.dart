import 'dart:async' show FutureOr;

import 'package:meta/meta.dart' show experimental;

/// Whether the content key for a destination and namespace should be replaced
/// before anything else is written under it.
///
/// The SDK asks this rather than carrying a schedule of its own, because the
/// right answer differs per application and per namespace: a namespace holding
/// a chat history and one holding a device's last-seen timestamp want very
/// different answers, and only the application knows which is which.
///
/// **Asked on the write path**, so a policy that awaits makes every encrypting
/// write wait for it. [FutureOr] is offered for the application that must
/// consult something, and a policy that does not await costs nothing.
///
/// Returning true cuts a fresh content key and conveys it. The superseded
/// conveyance record is **retained**, which is what lets an enrollment that
/// joins later read what was written before it.
@experimental
typedef CkRotationPolicy = FutureOr<bool> Function(CkRotationContext ck);

/// What a [CkRotationPolicy] is told about the content key it is deciding on.
///
/// Carries the destination as well as the namespace, because a content key is
/// scoped to the pair: the same namespace toward two atSigns is two keys, and
/// an application may want to treat them differently.
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

  /// The content key's own id.
  final String ckKid;

  /// When this content key was cut.
  ///
  /// The conveyance record's own `createdAt` where this client read it back,
  /// and this device's clock where this client cut it — so two devices can
  /// disagree by their clock skew, which is noise against any policy measured
  /// in days.
  final DateTime cutAt;

  /// Passed in rather than read, so a policy is testable without a clock.
  final DateTime now;

  /// How long ago this content key was cut.
  Duration get age => now.difference(cutAt);
}

/// The default [CkRotationPolicy]: replace a content key once it is a week old.
///
/// A week rather than a day because every replacement writes a conveyance
/// record that is then retained, so a short period accumulates records for the
/// lifetime of the atSign; and rather than a month because a week is already
/// the period this design measures an envelope's life in.
@experimental
bool rotateCkAfterOneWeek(CkRotationContext ck) =>
    ck.age >= const Duration(days: 7);

/// Whether the namespace key should be replaced before it is used again.
///
/// Replacing it is the expensive lever — one conveyance to every authorised
/// enrollment, and every peer cuts a fresh content key at its next write
/// because every key id it advertised has changed. So nothing in the SDK fires
/// it on a schedule: it fires on a cause, and an application deciding it is
/// time is one. This is where it is asked.
///
/// **Asked at two points**, because neither reaches every application on its
/// own. Before a content key is conveyed — but only where the destination is
/// this client's own atSign, since a sender cannot replace a peer's namespace
/// key. And once per authorised namespace at every client start, which is what
/// reaches an application that only ever writes to peers.
///
/// Returning true replaces the namespace key: fresh material is minted, the
/// previous private is retained so records sealed to it still open, and the new
/// private is conveyed to every authorised enrollment.
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

  /// The namespace the key protects.
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

/// The default [NskeyRotationPolicy]: never.
///
/// A policy that always says no rather than an absent one, so every call site
/// asks unconditionally and there is no null to forget.
@experimental
bool neverRotateNskey(NskeyRotationContext ns) => false;
