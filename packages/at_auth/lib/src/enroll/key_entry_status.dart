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
/// advertisement — carry the same field with the same values, and one
/// vocabulary is better served by one type than by a type per package with a
/// mapping between them. at_client depends on at_auth and not the reverse, so
/// this is the only direction the type can be shared in; `publicKeyKid` sits
/// here for the same reason.
///
/// An **open `String`**, and the two questions below are how a caller asks
/// about it. It was an `enum` with the values `active` and `retired` until
/// 2026-08-22, which made the vocabulary closed in a place it cannot be: this
/// status travels on records the atServer stores verbatim, and a newer client
/// may say something about a key that this build has never heard of.
///
/// The old enum did not *refuse* an unknown value — it flattened one, reading
/// anything it did not recognise as [retired]. Two things went wrong with that:
///
/// - **`retired` is the wrong reading for an unknown value, because it is
///   permissive in the direction that matters.** A retired key still verifies
///   what it signed; a revoked one must not. Reading an unrecognised token as
///   `retired` therefore left an older build happily verifying signatures made
///   with a key its owner has disowned.
/// - **It was lossy where a record is rebuilt from stored state.** A key
///   package advertisement is composed afresh on every reconcile from the
///   keyfile, whose own status vocabulary is open for the same reasons this
///   one is; flattening the keyfile's token on the way out republished the
///   owner's record with their statement about a key weakened.
///
/// So a token this build does not know is now carried through verbatim and
/// answers **no** to both questions below: it is not offered for new
/// operations, and it does not vouch for old ones. Unknown means *more*
/// restrictive than either value here, never less.
///
/// **Do not change any existing value below.** They are published on records
/// that other clients and other at_client implementations already read.
class KeyEntryStatus {
  const KeyEntryStatus._();

  /// Offered for new operations. The default when a record omits the field,
  /// which is how every record that has never rotated spells it.
  static const String active = 'active';

  /// Withdrawn from new operations, kept because it is what verifies or opens
  /// what it already produced.
  static const String retired = 'retired';

  /// The tokens this version knows about. For warn-level tooling only —
  /// never reject a value for not being in this set, and never decide with it
  /// (see [vouchesForPastOperations]).
  static const Set<String> known = {active, retired};

  /// Reads a wire `status`. Absent is [active]; anything else is the token
  /// itself, verbatim.
  ///
  /// Verbatim is the half of the forward-compatibility promise that tolerance
  /// would be worthless without: a reader that reshapes a value it does not
  /// understand has no way to be right about the reshaping, and whatever it
  /// produces is what a writer then emits.
  ///
  /// Today no caller reads an `_apsk` record and republishes its entries —
  /// every `_apsk` writer composes from local key material — so for that
  /// record this is a property of the reader/writer pair rather than of a live
  /// path. It is a live path for the key package, which is rebuilt from the
  /// keyfile on every reconcile.
  ///
  /// A `status` that is not a string at all is malformed rather than unknown,
  /// and it is stringified rather than repaired. That keeps it out of both
  /// [active] and [retired] — which is the answer that uses the key for
  /// nothing — and keeps what was actually written visible in a log.
  static String fromWire(Object? value) => value == null ? active : '$value';

  /// Whether [status] may be chosen for something **new** — a signer picking a
  /// key to sign with, a sender picking a key to seal to.
  ///
  /// Only [active]. Every other token, known or not, is a statement that the
  /// owner has withdrawn the key from new use.
  static bool offersNewOperations(String status) => status == active;

  /// Whether [status] still vouches for what the key already did — verifying a
  /// stored envelope or chain link that names it.
  ///
  /// [active] and [retired], because retirement withdraws the future and keeps
  /// the past. **Not `known.contains(status)`**, which would be the same answer
  /// today and the wrong one the moment a value like `revoked` is added: a
  /// token joins [known] by being understood, not by being trusted, and the
  /// first token anyone adds here is likely to be one that must fail this.
  static bool vouchesForPastOperations(String status) =>
      status == active || status == retired;
}
