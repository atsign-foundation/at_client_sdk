/// The nskey subsystem's wire vocabulary — reserved record names and
/// provider ids — in one place.
///
/// Every name here is **frozen wire vocabulary**: records on live atServers
/// already carry these spellings — several as immutable or write-once records
/// — so a changed byte strands data rather than renaming it. Each emitted
/// form is pinned as a raw string in `test/wire_literal_pins_test.dart`; an
/// intended change (there should be none) edits the pin in the same commit,
/// and that edit is the review. The spec's table of these shapes is
/// `docs/projects/pq/design.md` §1.3.
///
/// | record             | shape                                          |
/// |--------------------|------------------------------------------------|
/// | advertisement      | `public:__nskey.<ns>@<owner>`                  |
/// | nskey mint lock    | `_nskeylock.<ns>@<owner>`                      |
/// | CK conveyance      | `[@<recipient>:]<ckKid>.__ck.<ckNs>@<sender>`  |
/// | current-CK pointer | `__ckcur.<destination>.<ckNs>@<atSign>`        |
/// | signing root       | `public:pq_signing_root@<atSign>`              |
/// | root mint lock     | `_rootlock@<atSign>`                           |
///
/// At-rest ids freeze the same way — existing keyfiles hold them and scans
/// match on them: the `nskey.<ns>.<kid>` AtKeys id and the `__nskey.<kid>`
/// substrate secret name (both below), plus the root's `root:<algo>:<n>` slot
/// family, whose grammar lives in `AtKeys.keyIdPrefix`/`AtKeys.isRoleKeyId`
/// with `PqSigningRoot.keyIdRole` naming the role.
///
/// Deliberately absent: each payload's version constant stays beside its
/// codec (`nskeyAdvertisementVersion`, `PqSigningRoot.currentVersion`, the
/// signed-envelope version). The formats version independently, and one
/// shared constant would move them in lockstep.
library;

import 'package:at_commons/at_commons.dart' show AtKey, Metadata;

/// The record name an nskey advertisement is published under, in the
/// namespace the key serves: `public:__nskey.<ns>@<owner>`.
const String nskeyAdvertisementRecordName = '__nskey';

/// The at-key an nskey's public half is published under.
///
/// The **double** underscore is what makes eager publication both safe and
/// workable. Safe: an unauthenticated scan ignores `showhidden`, and a
/// `public:__` key is revealed only *by* `showhidden`, so an outsider cannot
/// enumerate which namespaces — which apps — an atSign uses, while `plookup`
/// still serves the key to anyone who knows the namespace. Workable: a *single*
/// underscore key is hidden from every scan but is written with **commit id -1**,
/// so it sits outside the commit log and sync can never push it.
AtKey nskeyAdvertisementKey(String owner, String namespace) => AtKey()
  ..key = nskeyAdvertisementRecordName
  ..namespace = namespace
  ..sharedBy = owner
  ..metadata = (Metadata()..isPublic = true);

/// The record name of the mint/rotate interlock: `_nskeylock.<ns>@<owner>`.
const String nskeyMintLockRecordName = '_nskeylock';

/// The at-key of the mint/rotate interlock for `(owner, namespace)`.
///
/// The metadata is contract, not tuning: the atServer's refusal of a second
/// **immutable** create is the interlock itself, and the [ttl] is the crash
/// backstop that stops a dead holder blocking its own atSign forever — long
/// enough that an ordinary mint never races its own expiry. The design lives
/// on `MintLock`.
AtKey nskeyMintLockKey(String owner, String namespace,
        {Duration ttl = mintLockTtl}) =>
    AtKey()
      ..key = nskeyMintLockRecordName
      ..namespace = namespace
      ..sharedBy = owner
      ..metadata = (Metadata()
        ..immutable = true
        ..ttl = ttl.inMilliseconds);

/// How long a mint lock survives unreleased.
///
/// A crash backstop, not a budget: a holder that dies mid-mint must not block
/// its own atSign forever. One value for every lock, because the thing it is
/// sized against — how long a mint can legitimately take — does not vary by
/// which record is being minted.
const Duration mintLockTtl = Duration(minutes: 2);

/// The leading segment of the current-CK pointer record:
/// `__ckcur.<destination>.<ckNs>@<atSign>`.
const String currentCkPointerRecordName = '__ckcur';

/// The at-key remembering which CK [sharedBy] is currently writing under for
/// [destination], namespaced by the namespace the nskey resolved to — matching
/// the CK's own scope.
///
/// The destination's `@` is stripped — the emitted segment is `bob`, not
/// `@bob` — and the double underscore hides the record from an ordinary scan.
AtKey currentCkPointerKey(
        {required String? sharedBy,
        required String destination,
        required String ckNs}) =>
    AtKey()
      ..key = '$currentCkPointerRecordName.${destination.replaceAll('@', '')}'
      ..namespace = ckNs
      ..sharedBy = sharedBy
      ..metadata = Metadata();

/// The record name of the atSign's signing root:
/// `public:pq_signing_root@<atSign>`, no namespace.
const String pqSigningRootRecordName = 'pq_signing_root';

/// The at-key the signing root is published under.
///
/// **Mutable**, like the nskey advertisement beside it. The root is an
/// ordinary signing key (`docs/projects/pq/decisions.md` 101), so retiring one
/// entry and advertising its successor is a rewrite of this record — which an
/// immutable record makes unimplementable. What immutability
/// was actually doing here is stopping two of the owner's privileged
/// enrollments each minting a root, and that job moves to
/// [pqSigningRootMintLockKey].
AtKey pqSigningRootKey(String atSign) => AtKey()
  ..key = pqSigningRootRecordName
  ..sharedBy = atSign
  ..metadata = (Metadata()..isPublic = true);

/// The record name of the signing root's mint interlock: `_rootlock@<atSign>`.
const String pqSigningRootMintLockRecordName = '_rootlock';

/// The at-key of the signing root's mint interlock.
///
/// A self key with **no namespace**, matching the record it guards: the root
/// is atSign-level, which is exactly what distinguishes it from an nskey. The
/// single underscore hides it from every scan and keeps it out of the commit
/// log, which is right for a record whose only reader is the atServer's own
/// refusal — it is taken and released remotely and must never ride sync.
///
/// The metadata is contract, not tuning, for the same reason
/// [nskeyMintLockKey]'s is: the refusal of a second **immutable** create is
/// the interlock, and [ttl] is the crash backstop.
AtKey pqSigningRootMintLockKey(String atSign, {Duration ttl = mintLockTtl}) =>
    AtKey()
      ..key = pqSigningRootMintLockRecordName
      ..sharedBy = atSign
      ..metadata = (Metadata()
        ..immutable = true
        ..ttl = ttl.inMilliseconds);

/// The record-name segment of a CK conveyance, between the `ckKid` and the
/// namespace the content key lives in.
const String ckConveyanceRecordName = '__ck';

/// The `.__ck.` boundary a conveyance key string is parsed on. Derived from
/// [ckConveyanceRecordName] so the builder and the parser cannot disagree by
/// a byte.
const String ckConveyanceMarker = '.$ckConveyanceRecordName.';

/// The at-key the CK for [value] was conveyed under.
///
/// A conveyance mirrors the value's own addressing —
/// `<ckKid>.__ck.<ckNs>@<owner>` for self data,
/// `@<recipient>:<ckKid>.__ck.<ckNs>@<sender>` for a share. Deriving it from
/// the value rather than from the nskey owner alone is what keeps the inbound
/// case addressable, since there sender and recipient are different atSigns.
///
/// [ckNs] is the namespace the nskey resolved to, **not** the value's own. One
/// conveyance therefore serves every namespace beneath it — which is what
/// makes an AtCollection sub-collection viable, since its namespace carries a
/// per-item id and would otherwise need a conveyance record per item.
AtKey ckConveyanceKey(AtKey value, String ckKid, String ckNs) => AtKey()
  ..key = '$ckKid.$ckConveyanceRecordName'
  ..namespace = ckNs
  ..sharedBy = value.sharedBy
  ..sharedWith = value.sharedWith
  ..metadata = Metadata();

/// Splits a conveyance key string into the CK it carries, the namespace that
/// CK lives in, and the nskey owner whose cache scope it belongs to — or
/// null if it is not a conveyance record.
///
/// Parsed by hand rather than through `AtKey.fromString`, which cuts a key
/// at its **last** dot: `abc.__ck.app_1.my_apps@alice` comes back with
/// namespace `my_apps`, and evicting under that would miss the entry and
/// leave the CK live. The `.__ck.` marker is the real boundary and a
/// multi-segment namespace survives it.
///
/// `nskeyOwner` is the recipient prefix when the key carries one, else the
/// record owner — the same `sharedWith ?? sharedBy` rule every writer of the
/// CK cache uses, so an observed deletion lands on the entry the write
/// created: a self conveyance `…@alice` and an inbound one `@alice:…@bob`
/// both scope to alice, and an outbound share `@bob:…@alice` scopes to bob.
({String nskeyOwner, String ckKid, String ckNs})? parseCkConveyanceKey(
    String key) {
  // `@recipient:` on an inbound conveyance, and `@owner` on every one. What
  // is left is `<ckKid>.__ck.<ckNs>`.
  var body = key.trim();
  if (body.startsWith('cached:')) body = body.substring('cached:'.length);
  String? recipient;
  final colon = body.indexOf(':');
  if (colon >= 0) {
    recipient = body.substring(0, colon);
    body = body.substring(colon + 1);
  }
  final at = body.lastIndexOf('@');
  if (at <= 0) return null;
  final owner = body.substring(at);
  body = body.substring(0, at);

  final marker = body.indexOf(ckConveyanceMarker);
  if (marker <= 0) return null;
  final ckKid = body.substring(0, marker);
  final ckNs = body.substring(marker + ckConveyanceMarker.length);
  if (ckKid.isEmpty || ckNs.isEmpty) return null;
  return (nskeyOwner: recipient ?? owner, ckKid: ckKid, ckNs: ckNs);
}

/// The reserved substrate `Secret`-name prefix an nskey private travels
/// under: `__nskey.<nskeyKid>`, in the namespace the key belongs to.
const String nskeySecretNamePrefix = '__nskey.';

/// The prefix of every filed nskey private's `AtKeys` id.
const String nskeyKeyfileIdPrefix = 'nskey.';

/// The `AtKeys` id a filed nskey private is stored under:
/// `nskey.<namespace>.<nskeyKid>`. The namespace is part of it deliberately —
/// kids are truncated hashes and are not unique across namespaces. The kid
/// never contains a dot, so the **last** dot is the parse boundary even for a
/// multi-segment namespace.
String nskeyKeyfileIdFor(String namespace, String nskeyKid) =>
    '$nskeyKeyfileIdPrefix$namespace.$nskeyKid';

// ---------------------------------------------------------------------------
// Provider ids — the `appMetadata.providerId` every record is stamped with,
// and what routes a read back to the scheme that wrote it. As frozen as the
// record names: a stored record cites its id forever. The fourth id,
// `legacyCryptoProviderId`, is deliberately not here — it names the
// pre-pluggable default scheme, not nskey vocabulary, and lives beside
// `CryptoConfig`, which is what consumes it.
// ---------------------------------------------------------------------------

/// Wire id of the CK-conveyance provider.
///
/// The id names the **role** (`at/nskey`) and then every algorithm a reader
/// needs code for: the KEM the content key is encapsulated under, and the AEAD
/// wrapping it inside the `pqSeal` envelope. Anything a reader can discover from
/// the value itself — the envelope version, `ckKid`, `nskeyKid` — stays out.
///
/// That is what makes an algorithm change graceful rather than a flag day: a
/// reader registers every scheme it supports, values route by their own id so
/// old ones never stop opening, and a writer can *decide* whether a recipient
/// can read a scheme instead of guessing.
/// [mlKemNskeyCryptoProviderId] is the second one, and it coexists with this
/// one exactly as this doc anticipated.
const String nskeyCryptoProviderId = 'at/nskey/XWING/AES/GCM';

/// Wire id of the CK-conveyance provider for the **no-hybrid** KEM.
///
/// The second id the [nskeyCryptoProviderId] doc anticipated, and the reason
/// it is a second id rather than a field: a record routes back to its provider
/// by this string on every read, so a conveyance sealed under either KEM keeps
/// opening for as long as its id resolves — no flag day, and no reader that
/// has to guess.
const String mlKemNskeyCryptoProviderId = 'at/nskey/MLKEM1024/AES/GCM';

/// The role prefix every CK-conveyance scheme shares, whatever its algorithms.
const String nskeyProviderFamily = 'at/nskey';

/// Wire id of the application-data provider.
///
/// This names the *algorithm* deliberately — it is the layer that needs
/// crypto-agility. A future `at/symmetric/AES/SIV` coexists with it, and values
/// written under this id keep their tag forever.
const String symmetricAesGcmCryptoProviderId = 'at/symmetric/AES/GCM';
