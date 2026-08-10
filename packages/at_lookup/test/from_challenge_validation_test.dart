import 'dart:convert';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/at_lookup_impl.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

/// A client refuses to sign a malformed `from:` challenge
void main() {
  const atSign = '@alice';

  /// The challenge shape an atServer must emit for a client:
  /// `data:_<uuid><atSign>:<uuid>`.
  String genuineChallenge({String forAtSign = atSign}) =>
      '_${Uuid().v4()}$forAtSign:${Uuid().v4()}';

  group('a genuine challenge is signed unchanged', () {
    test('the real server shape is accepted and returned byte-identical', () {
      final challenge = genuineChallenge();

      expect(validatedFromChallenge(challenge, atSign), challenge,
          reason: 'an honest server must see no behaviour change at all — the '
              'bytes signed are the bytes it sent');
    });

    test('an atSign passed without its @ still matches', () {
      // AtLookupImpl takes the atSign from its caller and does not normalise
      // it, while the challenge always carries the server's form.
      final challenge = genuineChallenge();

      expect(validatedFromChallenge(challenge, 'alice'), challenge);
    });

    test('an atSign containing a hyphen or digits is fine', () {
      // The parse splits on the LAST colon and matches the atSign by suffix,
      // so nothing here depends on the atSign's own charset.
      const odd = '@alice-2';
      final challenge = genuineChallenge(forAtSign: odd);

      expect(validatedFromChallenge(challenge, odd), challenge);
    });
  });

  group('a malformed challenge is refused', () {
    test('an envelope payload offered as a challenge is refused', () {
      // Imagine that a hostile atServer answers `from:`
      // with the JSON of an envelope payload, and a client that signs it
      // returns a valid envelope signature under the genuine APKAM key.
      final forged =
          jsonEncode({'nskeyKid': 'attacker-kid', 'publicKey': 'AAAA'});

      expect(() => validatedFromChallenge(forged, atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('no JSON object can ever be a valid challenge', () {
      for (final payload in <Object>[
        {'nskeyKid': 'k', 'publicKey': 'p'},
        {'a': 1},
        <String, Object>{},
        {'trailing': '_${const Uuid().v4()}$atSign:${const Uuid().v4()}'},
      ]) {
        final encoded = jsonEncode(payload);
        expect(encoded.endsWith('}'), isTrue);
        expect(() => validatedFromChallenge(encoded, atSign),
            throwsA(isA<UnAuthenticatedException>()),
            reason: 'refused: $encoded');
      }
    });

    test('appending a valid-looking suffix to JSON does not smuggle it', () {
      // The obvious way to try to satisfy both shapes at once. It stops being
      // valid JSON, which is the point — `verifyEnvelope` would not parse it.
      final smuggled = '${jsonEncode({'nskeyKid': 'k'})}'
          '_${const Uuid().v4()}$atSign:${const Uuid().v4()}';

      expect(() => validatedFromChallenge(smuggled, atSign),
          throwsA(isA<UnAuthenticatedException>()),
          reason: 'the session id must be `_<uuid>` and here it is a JSON '
              'object with one glued on');
    });
  });

  group('each component is checked', () {
    test('a challenge minted for another atSign is refused', () {
      // Otherwise a server holding a challenge issued to somebody else could
      // replay it through this client.
      final forBob = genuineChallenge(forAtSign: '@bob');

      expect(() => validatedFromChallenge(forBob, atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('a proof that is not a uuid is refused', () {
      expect(
          () => validatedFromChallenge(
              '_${const Uuid().v4()}$atSign:not-a-uuid', atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('a session id that is not `_<uuid>` is refused', () {
      expect(
          () => validatedFromChallenge(
              'session$atSign:${const Uuid().v4()}', atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('a challenge with no proof separator is refused', () {
      expect(
          () => validatedFromChallenge('_${const Uuid().v4()}$atSign', atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('an empty challenge is refused', () {
      expect(() => validatedFromChallenge('', atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });

    test('the inter-server proof: form is not accepted on a client path', () {
      // `from:` to a PEER server answers `data:proof:<sessionId><atSign>:<uuid>`
      // and carries a verifier-bound challenge. A client never speaks that
      // path, and the `proof:` prefix is not stripped by the client, so it must
      // not parse as a client challenge.
      final peerForm = 'proof:${genuineChallenge()}';

      expect(() => validatedFromChallenge(peerForm, atSign),
          throwsA(isA<UnAuthenticatedException>()));
    });
  });
}
