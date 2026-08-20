import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

/// The accepted incompatibility between at_client **3.14.0** and this tree,
/// pinned in both directions.
///
/// Step 3 replaced the released envelope — a flat
/// `{payload, signature, hashingAlgo, signingAlgo, enrollmentId}` map — with
/// RFC 7515 general serialization, and deleted the envelope as a
/// `PqPosture` axis, so no stage emits the old shape. Neither build can
/// read the other's envelope.
///
/// gkc ruled that **accepted rather than fixed**
/// (`docs/projects/pq/decisions.md` 95 rulings 2–3, amended 2026-08-14), on
/// reachability: the released reader is same-atSign only, hangs off
/// `AtClientSecretSharing.forClient` which nothing in 3.14.0 constructs, is
/// `@experimental`, and its own dartdoc opens "not yet suitable for production
/// secrets".
///
/// **An accepted break has to stay visible.** A break nobody asserts is
/// indistinguishable from one that quietly changed shape, and the ruling above
/// rests on knowing exactly what a released peer does with what this tree
/// emits. These are raw-literal pins on purpose: asserting through the
/// constants that produce the messages would follow a reworded refusal
/// silently, which is the whole failure a pin exists to stop.
void main() {
  /// Exactly what at_client 3.14.0's `wrapAndSign` emits — read from
  /// `lib/src/mixins/envelope_signing.dart` in the published archive, not
  /// reconstructed from memory of it. The payload is the raw object; the
  /// signature, algorithms and signer id are flat siblings of it.
  Map<String, Object?> releasedEnvelope() => {
        'payload': {'hello': 'world'},
        'signature': 'QUJD',
        'hashingAlgo': 'sha256',
        'signingAlgo': 'rsa2048',
        'enrollmentId': 'abc123',
      };

  /// What this tree emits: RFC 7515 general serialization.
  Map<String, Object?> currentEnvelope() => {
        'payload': 'eyJoZWxsbyI6IndvcmxkIn0',
        'signatures': [
          {'protected': 'eyJhbGciOiJSUzI1NiJ9', 'signature': 'QUJD'}
        ],
      };

  group('3.14.0 → this tree', () {
    test('a released envelope is refused, naming the payload', () {
      expect(
        () => SignedEnvelope.fromJson(releasedEnvelope()),
        throwsA(isA<AtSigningVerificationException>().having(
            (e) => e.toString(),
            'message',
            // RAW LITERAL, frozen: this is the message a released peer's
            // envelope produces here, and decisions.md 95 cites it.
            contains('an envelope must carry its payload as a string'))),
        reason: '3.14.0 carries the payload as a raw object, and this reader '
            'requires the base64url string RFC 7515 signs over',
      );
    });

    test('and it is the payload that stops it, not the missing array', () {
      // The two refusals are ordered, and which one fires is worth pinning
      // separately: a future reader that learned to take an object payload
      // would then fail on the signatures array instead, and the message in
      // the row above would silently stop being the one a released envelope
      // produces.
      final stringPayload = releasedEnvelope()..['payload'] = 'hello world';
      expect(
        () => SignedEnvelope.fromJson(stringPayload),
        throwsA(isA<AtSigningVerificationException>().having(
            (e) => e.toString(),
            'message',
            contains('an envelope must carry a non-empty signatures array'))),
      );
    });
  });

  group('this tree → 3.14.0', () {
    test('the released reader gets null where it requires a String', () {
      // 3.14.0 does, verbatim:
      //     final String signature = envelope['signature'];
      // against a general-serialization envelope, whose signatures live one
      // level down. This reproduces that indexing rather than importing the
      // released package: what is being pinned is the SHAPE mismatch, and it
      // is a property of the two documents, not of either codebase.
      final envelope = currentEnvelope();
      expect(envelope['signature'], isNull,
          reason: 'the field the released reader indexes does not exist here');
      expect(envelope['enrollmentId'], isNull);
      expect(envelope['hashingAlgo'], isNull);

      expect(
        () => envelope['signature'] as String,
        throwsA(isA<TypeError>()),
        reason: 'a released peer CRASHES on a null cast rather than refusing '
            'cleanly — decisions.md 95 ruling 2 listed that crash as something '
            'that could not happen, on the premise that no released reader '
            'existed. It does, so the crash is real and is pinned here',
      );
    });

    test('the signature it would need is nested, not absent', () {
      // The control: the envelope is not empty, it is shaped differently. A
      // pin that only showed `null` would pass equally against a broken
      // writer emitting nothing at all.
      final signatures = currentEnvelope()['signatures'] as List;
      expect(signatures, hasLength(1));
      expect((signatures.single as Map)['signature'], 'QUJD');
    });
  });
}
