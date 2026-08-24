import 'package:at_auth/at_auth.dart';
import 'package:test/test.dart';

/// A keyfile written by a newer client stays readable, and losslessly
/// flushable, by an older one.
///
/// `CryptographicMaterial.algorithm`'s dartdoc has stated that rule for the
/// whole document since the typed keyfile existed. `status` was an `enum`
/// parsed through a throwing `expectEnum`, so it was the one field that broke
/// it: a keyfile carrying any status a build did not know was refused **in its
/// entirety**, and the document is the user's key material. That made adding a
/// status value a breaking at-rest change forever — which is how it was
/// discovered, costing a rollout design that could not ship.
///
/// `pending` is used throughout as the unknown token because it is the value
/// this change exists to make shippable. Nothing here knows what it means, and
/// that is the point.
void main() {
  const unknown = 'pending';

  Map<String, dynamic> documentWith(String status) => {
        'version': AtKeys.supportedVersion,
        'atsign': '@alice',
        'enrollments': [
          {
            'enrollmentId': 'e1',
            'keys': [
              {
                'keyId': 'k1',
                'material': [
                  {
                    'role':
                        CryptographicMaterialRole.privateAuthentication,
                    'algorithm': CryptographicMaterialAlgorithm.rsa2048,
                    'createdAt': '2026-08-14T00:00:00.000Z',
                    'status': status,
                    'bytes': 'dmFsdWU=',
                  },
                ],
              },
            ],
          },
        ],
      };

  group('a status this build does not know', () {
    test('is read rather than refusing the whole document', () {
      // The arm that used to throw AtKeysValidationException. Everything else
      // in the document is ordinary, so a failure here is about the status
      // alone.
      final keys = AtKeys.fromJson(documentWith(unknown));

      expect(keys.keys, hasLength(1));
      expect(keys.keys.single.status, unknown,
          reason: 'the token is carried through verbatim, not normalised to '
              'something this build recognises');

      // The positive control: the identical document with a known status
      // reads too, so "it parsed" above is not passing for some unrelated
      // reason.
      expect(
          AtKeys.fromJson(documentWith(CryptographicMaterialStatus.retired))
              .keys
              .single
              .status,
          CryptographicMaterialStatus.retired);
    });

    test('round-trips unmodified on flush', () {
      // Tolerance on the read alone would be worse than refusing: toJson
      // re-encodes from the parsed materials, so a status that was dropped or
      // rewritten on the way in is a status silently destroyed on the next
      // flush — and the entry is key material.
      final flushed = AtKeys.fromJson(documentWith(unknown)).toJson();

      final part = ((flushed['enrollments'] as List).single['keys'] as List)
          .single['material']
          .single;
      expect(part['status'], unknown);
      expect(part['bytes'], 'dmFsdWU=',
          reason: 'the rest of the entry survives too — a status that '
              'round-trips while its bytes do not is no use to anyone');
    });

    test('is never selected as active', () {
      final keys = AtKeys.fromJson(documentWith(unknown));

      expect(keys.resolveAuthenticatingEnrollment(), isNull,
          reason: 'an unrecognised status has no rank, so it is not active. '
              'Reading it as active would hand a caller a key whose state '
              'this build cannot interpret');

      // The control, again on the identical document: the selector does find
      // an active material when there is one, so isNull above is the status
      // being skipped rather than the selector being broken.
      expect(
          AtKeys.fromJson(documentWith(CryptographicMaterialStatus.active))
              .resolveAuthenticatingEnrollment(),
          'e1');
    });

    test('cannot be moved by retireKey, and the refusal names it', () {
      final keys = AtKeys.fromJson(documentWith(unknown));

      expect(
          () => keys.retireKey('e1', 'k1'),
          throwsA(isA<ArgumentError>().having((e) => e.toString(), 'message',
              allOf(contains(unknown), contains('forward order')))),
          reason: 'this build cannot tell whether an unknown status sits '
              'before or after retired, and guessing a direction is how a '
              'future value gets silently reactivated');

      // The contrast arm: a known status moves, so the refusal above is about
      // the unknown token rather than retireKey being broken outright.
      final known = AtKeys.fromJson(documentWith(CryptographicMaterialStatus.active));
      known.retireKey('e1', 'k1');
      expect(known.keys.single.status, CryptographicMaterialStatus.retired);
    });

    test('may not be retired TO, either', () {
      final keys = AtKeys.fromJson(documentWith(CryptographicMaterialStatus.active));
      expect(
          () => keys.retireKey('e1', 'k1',
              to: CryptographicMaterialStatus.of(unknown)),
          throwsA(isA<ArgumentError>()),
          reason: 'moving a key INTO a status this build does not understand '
              'is the same guess in the other direction');
    });
  });

  group('the forward order is stated, not derived', () {
    test('ranks the known tokens and refuses to rank anything else', () {
      // Declaration index used to supply this for free, which also meant
      // reordering the enum silently redefined every transition check in the
      // package. It is a contract now, so it is pinned as one.
      expect(CryptographicMaterialStatus.rankOf(CryptographicMaterialStatus.active), 0);
      expect(CryptographicMaterialStatus.rankOf(CryptographicMaterialStatus.retired), 1);
      expect(CryptographicMaterialStatus.rankOf(CryptographicMaterialStatus.dead), 2);
      expect(CryptographicMaterialStatus.rankOf(CryptographicMaterialStatus.of(unknown)), isNull);
      expect(CryptographicMaterialStatus.rankOf(CryptographicMaterialStatus.of('')), isNull);
    });

    test('still refuses a backward move between known tokens', () {
      // The invariant the enum's index used to carry. If this passes while
      // the rank function is broken, the tolerance above was bought by
      // dropping the rule it was meant to preserve.
      final keys = AtKeys.fromJson(documentWith(CryptographicMaterialStatus.dead));
      expect(() => keys.retireKey('e1', 'k1', to: CryptographicMaterialStatus.retired),
          throwsA(isA<ArgumentError>()));
    });

    test('refuses to reactivate, as before', () {
      final keys = AtKeys.fromJson(documentWith(CryptographicMaterialStatus.retired));
      expect(() => keys.retireKey('e1', 'k1', to: CryptographicMaterialStatus.active),
          throwsA(isA<ArgumentError>()));
    });
  });

  test('an empty status is still malformed, not merely unknown', () {
    // The tolerance is for tokens, not for absent values. A blank status is a
    // damaged document and reads as one; widening the parse far enough to
    // accept it would make a corrupt file indistinguishable from a newer one.
    //
    // AtKeysParseException rather than AtKeysValidationException, and the
    // distinction is the point: an empty value never parsed, where a value
    // that parsed and then failed a rule is the validation case. Asserted by
    // observation — the first draft of this test guessed the other one.
    expect(() => AtKeys.fromJson(documentWith('')),
        throwsA(isA<AtKeysParseException>()));
  });

  test('an absent status still defaults to active', () {
    // Unchanged behaviour, pinned here because the parse moved: a document
    // that omits the field predates status entirely and its material is in
    // use.
    final document = documentWith(CryptographicMaterialStatus.active);
    ((document['enrollments'] as List).single['keys'] as List)
        .single['material']
        .single
        .remove('status');

    final keys = AtKeys.fromJson(document);
    expect(keys.keys.single.status, CryptographicMaterialStatus.active);
    expect(keys.resolveAuthenticatingEnrollment(), 'e1');
  });
}
