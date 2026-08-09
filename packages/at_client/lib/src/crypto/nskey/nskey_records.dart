/// The nskey subsystem's reserved record names, in one place.
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
/// | mint lock          | `_nskeylock.<ns>@<owner>`                      |
/// | CK conveyance      | `[@<recipient>:]<ckKid>.__ck.<ckNs>@<sender>`  |
/// | current-CK pointer | `__ckcur.<destination>.<ckNs>@<atSign>`        |
/// | signing root       | `public:pq_signing_root@<atSign>`              |
///
/// At-rest ids freeze the same way — existing keyfiles hold them and scans
/// match on them: the `nskey.<ns>.<kid>` AtKeys id and the `__nskey.<kid>`
/// substrate secret name (both below), plus `PqSigningRoot.keyId`'s
/// `pq_signing_root` slot family, which stays beside the class's
/// slot-overflow logic.
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
/// backstop that stops a dead holder blocking its own atSign forever. The
/// design lives on `NskeyMintLock`.
AtKey nskeyMintLockKey(String owner, String namespace,
        {required Duration ttl}) =>
    AtKey()
      ..key = nskeyMintLockRecordName
      ..namespace = namespace
      ..sharedBy = owner
      ..metadata = (Metadata()
        ..immutable = true
        ..ttl = ttl.inMilliseconds);

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
/// **Immutable** is the create-once property itself — the atServer refusing a
/// second create is what guarantees exactly one root is ever published; see
/// `PqSigningRoot` for why two would be unrecoverable.
AtKey pqSigningRootKey(String atSign) => AtKey()
  ..key = pqSigningRootRecordName
  ..sharedBy = atSign
  ..metadata = (Metadata()
    ..isPublic = true
    ..immutable = true);

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
