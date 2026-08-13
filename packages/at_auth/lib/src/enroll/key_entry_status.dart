/// Whether an advertised key entry is still offered for **new** operations.
///
/// Use-neutral, because an entry's `use` already names the operation a key
/// serves. Retirement withdraws the future, never the past: a retired signing
/// key still verifies the envelopes it signed, and a retired encapsulation key
/// still opens the records already sealed to it. What it forbids is a signer
/// signing with it, or a sender sealing to it, from now on.
///
/// Retaining rather than withdrawing is the whole point. Envelopes and chain
/// links are stored durably and verified long after they are written, so
/// dropping a key's entry outright would retroactively unverify everything ever
/// signed with it, and unopenably strand everything ever sealed to it.
///
/// **It lives here, in at_auth, because at_auth is the lower package.** All
/// three records that advertise keys — the `_apsk` signing advertisement
/// composed here, at_client's enrollment key package, and its nskey
/// advertisement — carry the same field with the same two values, and one
/// vocabulary is better served by one type than by a type per package with a
/// mapping between them. at_client depends on at_auth and not the reverse, so
/// this is the only direction the type can be shared in; `publicKeyKid` sits
/// here for the same reason.
enum KeyEntryStatus {
  active,
  retired;

  /// Reads a wire `status`. Absent — which is how every record that has never
  /// rotated spells it — is [active].
  ///
  /// **Anything else is [retired]**, rather than an error or a fallback to
  /// [active]. A value this build has never heard of was written by a newer
  /// client to say something narrower about the key than "offered for new
  /// operations", and reading an unknown state as active is the one answer that
  /// can make this build use a key whose owner has withdrawn it.
  static KeyEntryStatus fromWire(Object? value) =>
      value == null || value == active.name ? active : retired;
}
