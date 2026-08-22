import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, KeyEntryStatus, apskAdvertisement, apskSigningKeys;
import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf;
import 'package:at_client/src/signing/envelope_signature.dart';
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:test/test.dart';

import 'test_utils/envelope_tamper.dart';

/// Every form a published `_apsk` comes in, and the verify that reads them.
///
/// Two forms, because which one a record holds depends on what wrote it: the
/// **bare** RSA string, published by every released client, by a connection
/// with no enrollment id, and by the atServer for a plain-legacy enrollment;
/// and the **array**, composed by an enrolling client and written verbatim by
/// the atServer at approval. A reader accepts both.
///
/// Two properties carry the design. The **key's own declaration is
/// authoritative** — a lie in the envelope's `signingAlgo` can never select a
/// weaker routine than the published key calls for. And the **array is
/// unmistakable** — an old bare-RSA parser meeting one fails loudly rather
/// than mis-reading it, which is precisely why a plain-legacy enrollment
/// publishes the bare form instead.
void main() {
  const payload = 'the signable text';

  group('parseApskValue', () {
    test('a bare value is an RSA key, verbatim', () {
      final parsed = parseApskValue('MIIBIjANBgkq-not-really-but-bare');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'MIIBIjANBgkq-not-really-but-bare',
          reason: 'the bare form is what every published _apsk carries today, '
              'and what NoPorts parses — it must round-trip untouched');
    });

    test('a bare value reads as exactly ONE active rsa2048 entry', () {
      // The clause UC-G1.5 turns on and the one nothing asserted: not merely
      // that the bare form is read, but that it is read as a SINGLE active
      // entry. A reader that produced two, or one marked retired, would still
      // satisfy the verbatim test above while changing what a verifier
      // selects on.
      const bare = 'MIIBIjANBgkq-not-really-but-bare';
      final parsed = parseApskValue(bare);

      expect(parsed.keys, hasLength(1));
      expect(parsed.keys.single.alg, SigningAlgoType.rsa2048);
      expect(parsed.keys.single.status, KeyEntryStatus.active);
      expect(parsed.keys.single.pub, bare);
    });

    test('a structured value that advertises no keys is refused', () {
      expect(
          () => parseApskValue('{"v":1,"signingAlgo":"mldsa65","pub":"AAEC"}'),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the array is the only structured form; anything else that '
              'starts with { advertises no key this build can read, and a '
              'guessed algorithm turns a key mismatch into silent acceptance '
              'of whatever the server sent');
    });

    test('an array value names the algorithm of the key it advertises', () {
      final array = jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(alg: SigningAlgoType.mldsa65, pub: 'AAEC')
      ]));

      final parsed = parseApskValue(array);
      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'AAEC',
          reason: 'this is the form an enrollment publishes, so it is the one '
              'an approver meets when verifying a freshly advertised key '
              'package');
    });

    test('an array of nothing understood is refused, not fallen back from', () {
      expect(
          () => parseApskValue('{"v":1,"keys":['
              '{"kid":"k1","use":"sign","alg":"post2030","pub":"AAEC"}]}'),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'no downgrade and no fallback to a derivable legacy key — '
              'the signature means something only if the verifier used the '
              'key the signer published');
    });

    test('an array skips what it cannot use and reads what it can', () {
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k1","use":"sign","alg":"post2030","pub":"AAEC"},'
          '{"kid":"k2","use":"sign","alg":"rsa2048","pub":"CCEC"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'CCEC');
    });

    test('the STRONGEST advertised algorithm wins, not the first listed', () {
      // The weaker key is listed first, so taking `advertised.first` — which
      // is what this did until the strength order existed — picks RSA. The
      // order entries arrive in is the signer's choice, and letting it decide
      // hands the algorithm to whoever wrote the advertisement.
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k1","use":"sign","alg":"rsa2048","pub":"AAEC"},'
          '{"kid":"k2","use":"sign","alg":"mldsa65","pub":"CCEC"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'CCEC');
    });

    test('and the same advertisement in the other order reads the same', () {
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k2","use":"sign","alg":"mldsa65","pub":"CCEC"},'
          '{"kid":"k1","use":"sign","alg":"rsa2048","pub":"AAEC"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.mldsa65);
      expect(parsed.publicKey, 'CCEC',
          reason: 'the verdict must not depend on listing order at all — a '
              'test that only pins the weak-first case would pass on a reader '
              'that simply took the last entry');
    });

    test('a retired signing key is still read, because it verifies history',
        () {
      // `_apsk` retains a key so envelopes it already signed keep verifying.
      // Skipping retired entries here would refuse exactly the history that
      // retirement exists to preserve. Nothing in this path signs.
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k1","use":"sign","alg":"rsa2048","pub":"AAEC",'
          '"status":"retired"}]}');

      expect(parsed.signingAlgo, SigningAlgoType.rsa2048);
      expect(parsed.publicKey, 'AAEC');
    });

    test('a status this build cannot read is NOT a verification candidate', () {
      // The asymmetry with the test above, and the reason `status` is an open
      // token rather than a two-valued enum. `retired` says "withdrawn from
      // new use, still vouches for the past". A token this build has never
      // seen says something else, and the likeliest something else - a key
      // whose owner has disowned it - is precisely one whose signatures must
      // STOP checking out here. Reading it as `retired`, which is what this
      // did until 2026-08-22, left an older build verifying forgeries.
      final parsed = parseApskValue('{"v":1,"keys":['
          '{"kid":"k1","use":"sign","alg":"mldsa65","pub":"AAEC",'
          '"status":"revoked"},'
          '{"kid":"k2","use":"sign","alg":"rsa2048","pub":"CCEC"}]}');

      expect(parsed.keys.map((k) => k.kid), ['k2'],
          reason: 'the revoked entry is not offered to the verifier at all');
      expect(parsed.signingAlgo, SigningAlgoType.rsa2048,
          reason: 'and it does not win the strength contest either - an '
              'entry that is dropped cannot select the algorithm');
    });

    test('an advertisement of nothing verifiable is refused, not half-read',
        () {
      // Same rule as an advertisement of algorithms this build does not know:
      // empty means refuse outright rather than fall back to a key derived
      // some other way.
      expect(
          () => parseApskValue('{"v":1,"keys":['
              '{"kid":"k1","use":"sign","alg":"mldsa65","pub":"AAEC",'
              '"status":"revoked"}]}'),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('the array form is unmistakable to a bare-RSA consumer', () {
      final array = jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(alg: SigningAlgoType.mldsa65, pub: 'AAEC')
      ]));

      // What an old parser does with the value: treat it as base64 RSA key
      // material. It must throw, never quietly produce a key.
      expect(() => base64Decode(array), throwsA(isA<FormatException>()),
          reason: 'NoPorts and its peers parse _apsk as a bare RSA key today; '
              'the array must fail their parse loudly, never mis-read — which '
              'is why a plain-legacy enrollment publishes the bare form and '
              'not this');
    });
  });

  group('the writer still emits the bare form', () {
    // UC-G1.5's writer arm, and it asserts the OPPOSITE of what that row said
    // until 2026-08-18. The row read "the current build never emits that
    // shape"; the build emits it deliberately, under the default posture,
    // because a single active rsa2048 entry is exactly what an un-upgraded
    // peer can still parse. Only a second key, or a non-rsa2048 key, forces
    // the array.
    // Valid base64: `ApskSigningKey.forPublicKey` derives each entry's `kid`
    // by decoding the key, so a placeholder that is not base64 fails in the
    // composer rather than in the assertion.
    final pub = base64Encode(utf8.encode('rsa-public-half'));

    ApkamSigningKeys rsa(String p) => ApkamSigningKeys(
        algorithm: SigningAlgoType.rsa2048, publicKey: p, privateKey: 'priv');

    test('one active rsa2048 key is spelled bare, not as the array', () {
      final value = apskValueOf(apskEntries(
          signing: const [], withdrawn: const [], authentication: rsa(pub)));

      expect(value, pub);
      expect(value, isNot(startsWith('{')),
          reason: 'a bare-RSA consumer base64-decodes this value; JSON where '
              'a bare key would do breaks everything already deployed');
    });

    test('a second key forces the array — so the assertion above discriminates',
        () {
      // The control. Without it the test above is satisfied by a writer that
      // can only ever emit the bare form, and the rule it names would be
      // untested rather than proven.
      final value = apskValueOf(apskEntries(
          signing: [rsa(pub), rsa(base64Encode(utf8.encode('second')))],
          withdrawn: const [],
          authentication: null));

      expect(value, startsWith('{'));
    });

    test('and a non-rsa2048 key forces it too', () {
      final value = apskValueOf(apskEntries(signing: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.mldsa65,
            publicKey: base64Encode(utf8.encode('mldsa-public-half')),
            privateKey: 'priv')
      ], withdrawn: const [], authentication: null));

      expect(value, startsWith('{'));
    });

    test('a withdrawn key is advertised with the status it was handed', () {
      // The composer decides what the record says about every key the
      // enrollment has ever used, because the advertisement is rewritten whole
      // on every publish. It used to stamp every withdrawn entry `retired`,
      // which is only correct for the tokens it can read.
      final entries = apskEntries(signing: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.mldsa65,
            publicKey: base64Encode(utf8.encode('mldsa-public-half')),
            privateKey: 'priv')
      ], withdrawn: [
        (algorithm: SigningAlgoType.rsa2048, publicKey: pub, status: 'revoked')
      ], authentication: null);

      expect(entries.map((e) => e.status).toList(),
          [KeyEntryStatus.active, 'revoked'],
          reason: 'raw literal on the right: the composer writes the token '
              'through rather than substituting one it knows');
      expect(jsonDecode(apskValueOf(entries))['keys'][1]['status'], 'revoked',
          reason: 'and that is what lands on the record');
    });

    test('but the verify reader will not check a signature against it', () {
      // The asymmetry, deliberately, and pinned so nobody unifies the two
      // readers: at_auth's `apskSigningKeys` KEEPS an entry whose status it
      // cannot read, because the writers above republish what it returns and
      // deleting the entry would withdraw the key. at_client's verify reader
      // DROPS it, because trusting a signature made with a key its owner may
      // have disowned is the one outcome nothing recovers from.
      final value = apskValueOf(apskEntries(signing: [
        ApkamSigningKeys(
            algorithm: SigningAlgoType.mldsa65,
            publicKey: base64Encode(utf8.encode('mldsa-public-half')),
            privateKey: 'priv')
      ], withdrawn: [
        (algorithm: SigningAlgoType.rsa2048, publicKey: pub, status: 'revoked')
      ], authentication: null));

      expect(apskSigningKeys(jsonDecode(value)).map((k) => k.alg).toList(),
          [SigningAlgoType.mldsa65, SigningAlgoType.rsa2048],
          reason: 'the writers\' reader keeps it, or republishing deletes it');
      expect(parseApskValue(value).keys.map((k) => k.alg).toList(),
          [SigningAlgoType.mldsa65],
          reason: 'the verifier\'s reader does not');
    });

    test('what it emits bare reads back as what it wrote', () {
      // The round trip, which is the property the row is really about: this
      // writer's output is this reader's input, and a change to either that
      // did not move the other would show up here.
      final value = apskValueOf(apskEntries(
          signing: const [], withdrawn: const [], authentication: rsa(pub)));
      final parsed = parseApskValue(value);

      expect(parsed.keys, hasLength(1));
      expect(parsed.keys.single.alg, SigningAlgoType.rsa2048);
      expect(parsed.keys.single.status, KeyEntryStatus.active);
      expect(parsed.keys.single.pub, pub);
    });
  });

  group('verifyEnvelope, every published form', () {
    late AtPkamKeyPair rsaPair;
    late ({Uint8List publicKey, Uint8List secretKey}) mlDsaPair;

    setUpAll(() async {
      rsaPair = AtChopsUtil.generateAtPkamKeyPair();
      mlDsaPair = await MlDsa65PureDartAlgo().generateKeyPair();
    });

    SignedEnvelope rsaEnvelope() => signEnvelope(payload,
        keys: [
          ApkamSigningKeys(
              algorithm: SigningAlgoType.rsa2048,
              publicKey: rsaPair.atPublicKey.publicKey,
              privateKey: rsaPair.atPrivateKey.privateKey)
        ],
        type: EnvelopeType.app);

    /// What a 4.x enrollment's signer produces: the same envelope shape,
    /// signed ML-DSA-65, naming that algorithm in its protected header.
    SignedEnvelope mlDsaEnvelope() => signEnvelope(payload,
        keys: [
          ApkamSigningKeys(
              algorithm: SigningAlgoType.mldsa65,
              publicKey: base64Encode(mlDsaPair.publicKey),
              privateKey: base64Encode(mlDsaPair.secretKey))
        ],
        enrollmentId: 'enroll-pq',
        type: EnvelopeType.app);

    /// [envelope] with its protected header replaced, so a test can make the
    /// envelope claim an algorithm its key does not match. The header is
    /// inside the signature, so this is a re-stamp rather than an edit — and
    /// it is the only way to build the mismatch at all.
    SignedEnvelope claimingAlg(SignedEnvelope envelope, String alg) =>
        envelope.claiming({'alg': alg, 'v': 1});

    /// The `_apsk` an ML-DSA enrollment publishes: what its client composed,
    /// written verbatim by the atServer at approval.
    String mlDsaApsk() => jsonEncode(apskAdvertisement(keys: [
          ApskSigningKey.forPublicKey(
              alg: SigningAlgoType.mldsa65,
              pub: base64Encode(mlDsaPair.publicKey))
        ]));

    test('a bare RSA _apsk verifies an RSA envelope — today\'s traffic',
        () async {
      await verifyEnvelope(rsaEnvelope(),
          signerPublicKey: rsaPair.atPublicKey.publicKey,
          expecting: EnvelopeType.app);
    });

    test('an array ML-DSA _apsk verifies an ML-DSA envelope', () async {
      // The whole approval path in one assertion: this is the value the
      // atServer publishes from what the enrolling client composed, and the
      // approver verifies the advertised key package against exactly it.
      await verifyEnvelope(mlDsaEnvelope(),
          signerPublicKey: mlDsaApsk(), expecting: EnvelopeType.app);
    });

    test('an array RSA _apsk refuses an envelope claiming ML-DSA-65', () async {
      final apsk = jsonEncode(apskAdvertisement(keys: [
        ApskSigningKey.forPublicKey(
            alg: SigningAlgoType.rsa2048, pub: rsaPair.atPublicKey.publicKey)
      ]));
      final envelope = claimingAlg(rsaEnvelope(), 'ML-DSA-65');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: apsk, expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the array carries the algorithm explicitly, so the claim '
              'cannot select a routine the published key does not call for');
    });

    test('signEnvelope signs ML-DSA when asked, and the result verifies',
        () async {
      final envelope = signEnvelope(payload,
          keys: [
            ApkamSigningKeys(
                algorithm: SigningAlgoType.mldsa65,
                publicKey: base64Encode(mlDsaPair.publicKey),
                privateKey: base64Encode(mlDsaPair.secretKey))
          ],
          enrollmentId: 'enroll-pq',
          type: EnvelopeType.app);
      final entry = envelope.signature;
      expect(entry.alg, 'ML-DSA-65');
      expect(base64Decode(base64.normalize(entry.signature)).length, 3309,
          reason: 'an ML-DSA-65 signature is 3309 bytes — an RSA-sized '
              'signature here means the sign dispatch ignored the algorithm '
              'the keys name');

      final apsk = mlDsaApsk();
      await verifyEnvelope(envelope,
          signerPublicKey: apsk, expecting: EnvelopeType.app);

      await expectLater(
          () => verifyEnvelope(envelope.withPayloadJson('a different text'),
              signerPublicKey: apsk, expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()));
    });

    test('signEnvelope refuses an algorithm it has no signing code for', () {
      expect(
          () => signEnvelope(payload,
              keys: [
                ApkamSigningKeys(
                    algorithm: SigningAlgoType.ecc_secp256r1,
                    publicKey: 'x',
                    privateKey: 'y')
              ],
              type: EnvelopeType.app),
          throwsA(isA<ArgumentError>()));
    });

    test('a tampered ML-DSA envelope fails', () async {
      final apsk = mlDsaApsk();
      final envelope = mlDsaEnvelope().withPayloadJson('a different text');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: apsk, expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'control: the ML-DSA branch must actually verify, or the '
              'happy path above proves routing and nothing else');
    });

    test(
        'an envelope claiming rsa2048 against an ML-DSA _apsk is '
        'refused', () async {
      final apsk = mlDsaApsk();

      await expectLater(
          () => verifyEnvelope(rsaEnvelope(),
              signerPublicKey: apsk, expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'the key\'s declaration is authoritative — the claim cannot '
              'select a weaker routine than the published key calls for');
    });

    test('an envelope claiming ML-DSA-65 against a bare RSA key is refused',
        () async {
      final envelope = claimingAlg(rsaEnvelope(), 'ML-DSA-65');

      await expectLater(
          () => verifyEnvelope(envelope,
              signerPublicKey: rsaPair.atPublicKey.publicKey,
              expecting: EnvelopeType.app),
          throwsA(isA<AtSigningVerificationException>()),
          reason: 'a bare key is RSA by definition; an envelope claiming '
              'otherwise is lying about something, and the lie fails');
    });
  });
}
