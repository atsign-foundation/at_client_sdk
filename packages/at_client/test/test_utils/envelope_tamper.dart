import 'dart:convert' show base64Url, jsonEncode, utf8;

import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope;

/// Tamper levers for [SignedEnvelope], shared by every test that needs to
/// produce an envelope somebody has interfered with.
///
/// They exist because the type is immutable and validated: a test can no
/// longer reach in and assign a member. That is the point — the reason these
/// helpers are worth having in one place is the reason the type is worth
/// having at all. The old way, mutating a `Map`, let a test write a forgery
/// the verifier never looks at (a top-level `'signature'`, say) and pass for
/// the *absence* of a forgery.
///
/// Each returns a new envelope through `fromJson`, so a tamper that breaks the
/// structure is refused here rather than silently producing something no
/// verifier would recognise.
extension EnvelopeTamper on SignedEnvelope {
  /// This envelope with its payload replaced by [payloadB64] verbatim.
  SignedEnvelope withPayload(String payloadB64) =>
      SignedEnvelope.fromJson({...toJson(), 'payload': payloadB64});

  /// This envelope with its payload replaced by the base64url encoding of
  /// [json] — the readable form of [withPayload].
  SignedEnvelope withPayloadJson(Object? json) =>
      withPayload(b64u(jsonEncode(json)));

  /// This envelope with [member] of its sole signature entry replaced.
  SignedEnvelope withEntryMember(String member, String value) =>
      SignedEnvelope.fromJson({
        ...toJson(),
        'signatures': [
          {...signature.toJson(), member: value}
        ],
      });

  /// This envelope re-stamped with a different protected header, which is how
  /// a test builds a claim mismatch: `alg` and `kid` are inside the
  /// signature, so they cannot be edited — only re-signed or forged.
  SignedEnvelope claiming(Map<String, Object?> header) =>
      withEntryMember('protected', b64u(jsonEncode(header)));

  /// This envelope with its `signatures` array replaced wholesale — for the
  /// structural refusals (empty, non-object entries, a missing member).
  Map<String, Object?> withRawSignatures(Object? signatures) =>
      {...toJson(), 'signatures': signatures};
}

/// Unpadded base64url of [text], the encoding every envelope member uses.
String b64u(String text) =>
    base64Url.encode(utf8.encode(text)).replaceAll('=', '');

/// Decodes unpadded base64url back to text.
String unb64u(String s) =>
    utf8.decode(base64Url.decode(base64Url.normalize(s)));
