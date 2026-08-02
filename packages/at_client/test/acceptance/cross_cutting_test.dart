/// Cross-cutting acceptance — invariants testable against EVERY use case.
///
/// These are not a cluster in the A/B sequence; they are properties every
/// scenario above must preserve. Treat a failure here as a design violation,
/// not a scenario bug.
///
/// Catalogue: `docs/projects/pq/acceptance.md` section 13.
library;

import 'package:test/test.dart';

import 'blockers.dart';

void main() {
  group('cross-cutting invariants', () {
    test('reads are universal', () {
      // A client decrypts anything ever written to it (all providers retained);
      // upgrading only ever ADDS read-capability.
      fail('not implemented');
    }, skip: b1);

    test('writes are gated by reader readiness', () {
      // A value/notification is only written in a scheme EVERY required reader
      // supports; otherwise legacy (3.x), or REFUSED under
      // disallowLegacyEncryption = true.
      fail('not implemented');
    }, skip: r1);

    test('appMetadata.providerId is authoritative on keys and frames', () {
      // Present on BOTH stored keys and notification frames, with the no-ns
      // shapes: at/nskey/XWING/AES/GCM ->
      //   {providerId, recipientKind, ckKid, nskeyKid};
      // at/symmetric/AES/GCM -> {providerId, ckKid, iv}. A providerId names
      // every algorithm a reader needs code for, so a scheme change is
      // rollable rather than a flag day.
      //
      // "and frames" is not the whole story: it must also survive a LOOKUP.
      // The atServer does not return appMetadata on a cross-atSign lookup
      // today, so every cross-atSign read falls back to legacy — for every
      // provider, not just the PQ ones (decisions.md section 17).
      fail('not implemented');
    }, skip: b1);

    test('no RSA in any confidentiality path for a fully-PQ interaction', () {
      // Auth, enrollment conveyance, self, shared, and notification paths.
      fail('not implemented');
    }, skip: b1);

    test('ML-DSA APKAM auth is record-authoritative', () {
      // PQ auth verifies against the enrollment record's single apkamPublicKey
      // using the RECORD signingAlgo — _getSigningAlgoType reads the record,
      // NEVER the client-supplied wire value.
      fail('not implemented');
    }, skip: ss2);

    test('pqpublickey is create-once; the published nskey is not', () {
      // A second pqpublickey create is rejected, never an overwrite — it is the
      // root and never rotates. public:__nskey.<ns>@owner is mutable BY DESIGN,
      // because nskey-keypair rotation has to overwrite it; two of the owner's
      // enrollments are kept apart by the short-ttl immutable lock
      // _nskeylock.<ns>@owner, and substitution is prevented by the APKAM
      // signature over the advertised envelope, not by the write mode.
      fail('not implemented');
    }, skip: ss4);

    test('a published nskey is fetchable but not enumerable', () {
      // public:__nskey.<ns>@owner resolves on an exact plookup, cross-atSign, and
      // appears in NO scan — with or without showhidden, authenticated or not.
      // A guaranteed protocol property (_apsk already relies on it); this is a
      // regression guard against a server change retiring it.
      fail('not implemented');
    }, skip: ss4);

    test('advertised recipient keys are signed and verified', () {
      // Every advertised encapsulation key — the per-enrollment key package, the
      // published nskey public half, and public:pqpublickey@owner — is an
      // APKAM-signed envelope verified against the enrollment's _apsk THE SAME
      // WAY same-atSign and cross-atSign, BEFORE encapsulating to it. A
      // tampered, unsigned, or wrong-signer advertised key is REJECTED. The
      // atServer keeps every approved enrollment's _apsk present (fetchable
      // without a client publish) and write-restricted (a cross-enrollment
      // overwrite is refused).
      fail('not implemented');
    }, skip: ss4);

    test('performance is measured, not assumed', () {
      // PKAM-auth and put/get latency deltas vs the legacy RSA/AES path are
      // measured on one reference low-end device by a bench harness landed WITH
      // B-1. The harness is the durable artefact, re-run on every later
      // key-shape change. The ceiling is pinned when the harness lands — a
      // measured budget, not a guessed number.
      fail('not implemented');
    }, skip: b1);
  });
}
