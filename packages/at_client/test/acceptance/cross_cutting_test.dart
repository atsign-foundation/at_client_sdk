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
      // shapes: at/nskey -> {providerId, recipientKind, ckKid};
      // at/symmetric/AES/GCM -> {providerId, ckKid, iv}.
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

    test('pqpublickey and the promoted public: nskey are create-once', () {
      // A second create is rejected, never an overwrite. The owner-only self
      // at-key nskey.<ns>@owner is an ordinary at-key — it syncs and is
      // re-written on rotation; only its promotion to public: is immutable.
      fail('not implemented');
    }, skip: ss4);

    test('advertised recipient keys are signed and verified', () {
      // Every advertised encapsulation key — the per-enrollment key package, the
      // published nskey public half, and public:pqpublickey@owner — is an
      // APKAM-signed envelope verified against the enrollment's _apsk THE SAME
      // WAY same-atSign and cross-atSign, BEFORE encapsulating to it. A
      // tampered, unsigned, or wrong-signer advertised key is REJECTED.
      fail('not implemented');
    }, skip: ss4);

    test('performance is measured, not assumed', () {
      // PKAM-auth and put/get latency deltas vs the legacy RSA/AES path are
      // measured on one reference low-end device by a bench harness landed WITH
      // B-1. The harness is the durable artefact, re-run on every later
      // key-shape change. The ceiling is pinned when the harness lands — a
      // measured budget, not a guessed number.
      fail('not implemented');
    }, skip: vectors);
  });
}
