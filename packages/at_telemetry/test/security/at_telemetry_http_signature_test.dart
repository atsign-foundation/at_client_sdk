import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

import '../helpers/callback_signer.dart';
import '../helpers/sequence_random.dart';

void main() {
  const String path = '/v1/logs';
  const String keyId = '@alice';
  const String audience = '@collector';
  const int created = 1704067200;
  const String nonce = 'AAECAwQFBgcICQoLDA0ODw';
  const String input = 'at=("@method" "@path" "content-type" "content-digest" '
      '"at-telemetry-audience");created=$created;expires=${created + 300};'
      'nonce="$nonce";keyid="@alice";alg="rsa-v1_5-sha256";'
      'tag="at-telemetry-v1"';
  final List<int> body = utf8.encode('hello');

  late RsaKeyPair keys;
  late RsaKeyPair otherKeys;
  late AtTelemetrySigner signer;

  setUpAll(() {
    keys = RsaKeyPair.generate();
    otherKeys = RsaKeyPair.generate();
    signer = AtTelemetryRsaSigner.fromBase64(keys.atPrivateKey.privateKey);
  });

  Future<AtTelemetryHttpSignature> signHello({
    String keyId = keyId,
    String audience = audience,
  }) {
    return AtTelemetryHttpSignature.sign(
      body: body,
      path: path,
      keyId: keyId,
      audience: audience,
      signer: signer,
      now: () => DateTime.fromMillisecondsSinceEpoch(
        created * 1000,
        isUtc: true,
      ),
      random: SequenceRandom(),
    );
  }

  AtTelemetryHttpSignature parseSigned(
    AtTelemetryHttpSignature signed, {
    String? input,
    String? signature,
    String? digest,
    String? audience,
  }) {
    return AtTelemetryHttpSignature.parse(
      input: input ?? signed.input,
      signature: signature ?? signed.signature,
      digest: digest ?? signed.digest,
      audience: audience ?? signed.audience,
    );
  }

  DateTime secondsAfterCreated(int seconds) {
    return DateTime.fromMillisecondsSinceEpoch(
      (created + seconds) * 1000,
      isUtc: true,
    );
  }

  group('AtTelemetryHttpSignature', () {
    group('sign', () {
      test('produces the expected headers', () async {
        final AtTelemetryHttpSignature signed = await signHello();

        expect(signed.keyId, keyId);
        expect(signed.created, created);
        expect(signed.expires, created + 300);
        expect(signed.nonce, nonce);
        expect(signed.input, input);
        expect(signed.audience, audience);
        expect(
          signed.digest,
          'sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:',
        );
        expect(signed.signature, matches(RegExp(r'^at=:[A-Za-z0-9+/]+=*:$')));
      });

      test('signs the expected signature base', () async {
        late List<int> message;
        await AtTelemetryHttpSignature.sign(
          body: body,
          path: path,
          keyId: keyId,
          audience: audience,
          signer: CallbackSigner((List<int> signed) async {
            message = signed;
            return Uint8List(256);
          }),
          now: () => secondsAfterCreated(0),
          random: SequenceRandom(),
        );

        expect(
          utf8.decode(message),
          '"@method": POST\n'
          '"@path": /v1/logs\n'
          '"content-type": application/x-protobuf\n'
          '"content-digest": '
          'sha-256=:LPJNul+wow4m6DsqxbninhsWHlwfp0JecwQzYpOLmCQ=:\n'
          '"at-telemetry-audience": @collector\n'
          '"@signature-params": ${input.substring(3)}',
        );
      });

      test('uses a new random nonce by default', () async {
        final AtTelemetryHttpSignature first =
            await AtTelemetryHttpSignature.sign(
          body: body,
          path: path,
          keyId: keyId,
          audience: audience,
          signer: signer,
        );
        final AtTelemetryHttpSignature second =
            await AtTelemetryHttpSignature.sign(
          body: body,
          path: path,
          keyId: keyId,
          audience: audience,
          signer: signer,
        );

        expect(first.nonce, hasLength(22));
        expect(first.nonce, isNot(second.nonce));
      });

      test('percent-encodes keyId and audience but keeps @', () async {
        final AtTelemetryHttpSignature signed =
            await signHello(keyId: '@alice bob', audience: '@col"lector');

        expect(signed.keyId, '@alice bob');
        expect(signed.input, contains('keyid="@alice%20bob"'));
        expect(signed.audience, '@col%22lector');
      });
    });

    group('verify', () {
      test('accepts a signature from the matching key', () async {
        final AtTelemetryHttpSignature parsed = parseSigned(await signHello());

        expect(
          await parsed.verify(
            path: path,
            publicKey: keys.atPublicKey.publicKey,
          ),
          isTrue,
        );
      });

      test('rejects the wrong public key', () async {
        final AtTelemetryHttpSignature parsed = parseSigned(await signHello());

        expect(
          await parsed.verify(
            path: path,
            publicKey: otherKeys.atPublicKey.publicKey,
          ),
          isFalse,
        );
      });

      test('rejects a public key that is not base64', () async {
        final AtTelemetryHttpSignature parsed = parseSigned(await signHello());

        expect(
          await parsed.verify(path: path, publicKey: 'not base64!'),
          isFalse,
        );
      });

      test('rejects a different path', () async {
        final AtTelemetryHttpSignature parsed = parseSigned(await signHello());

        expect(
          await parsed.verify(
            path: '/v1/other',
            publicKey: keys.atPublicKey.publicKey,
          ),
          isFalse,
        );
      });

      test('rejects tampered headers', () async {
        final AtTelemetryHttpSignature signed = await signHello();
        final Uint8List signatureBytes = base64Decode(
          signed.signature.substring(4, signed.signature.length - 1),
        );
        signatureBytes[0] ^= 1;

        final Map<String, AtTelemetryHttpSignature> tampered =
            <String, AtTelemetryHttpSignature>{
          'audience': parseSigned(signed, audience: '@mallory'),
          'digest': parseSigned(
            signed,
            digest: AtTelemetryHttpSignature.digestOf(utf8.encode('bye')),
          ),
          'input': parseSigned(
            signed,
            input: signed.input.replaceFirst('$created', '${created + 1}'),
          ),
          'keyid': parseSigned(
            signed,
            input: signed.input.replaceFirst('@alice', '@mallory'),
          ),
          'signature': parseSigned(
            signed,
            signature: 'at=:${base64Encode(signatureBytes)}:',
          ),
        };

        for (final MapEntry<String, AtTelemetryHttpSignature> entry
            in tampered.entries) {
          expect(
            await entry.value.verify(
              path: path,
              publicKey: keys.atPublicKey.publicKey,
            ),
            isFalse,
            reason: 'tampered ${entry.key}',
          );
        }
      });
    });

    group('parse', () {
      test('reads back the signed fields', () async {
        final AtTelemetryHttpSignature signed = await signHello();
        final AtTelemetryHttpSignature parsed = parseSigned(signed);

        expect(parsed.keyId, keyId);
        expect(parsed.created, created);
        expect(parsed.expires, created + 300);
        expect(parsed.nonce, nonce);
        expect(parsed.input, signed.input);
        expect(parsed.audience, signed.audience);
        expect(parsed.digest, signed.digest);
        expect(parsed.signature, signed.signature);
      });

      test('decodes a percent-encoded keyId', () async {
        final AtTelemetryHttpSignature parsed =
            parseSigned(await signHello(keyId: '@alice bob'));

        expect(parsed.keyId, '@alice bob');
      });

      test('throws FormatException for malformed headers', () async {
        final AtTelemetryHttpSignature signed = await signHello();
        final String shortDigest =
            'sha-256=:${base64Encode(List<int>.filled(31, 0))}:';
        final String shortSignature =
            'at=:${base64Encode(List<int>.filled(255, 0))}:';

        final Map<String, AtTelemetryHttpSignature Function()> invalid =
            <String, AtTelemetryHttpSignature Function()>{
          'wrong alg': () => parseSigned(
                signed,
                input: signed.input.replaceFirst('rsa-v1_5', 'rsa-pss'),
              ),
          'wrong tag': () => parseSigned(
                signed,
                input: signed.input.replaceFirst('v1"', 'v2"'),
              ),
          'short nonce': () => parseSigned(
                signed,
                input: signed.input.replaceFirst(nonce, nonce.substring(1)),
              ),
          'expires equals created': () => parseSigned(
                signed,
                input: signed.input.replaceFirst(
                    'expires=${created + 300}', 'expires=$created'),
              ),
          'lifetime over 300 seconds': () => parseSigned(
                signed,
                input: signed.input.replaceFirst(
                    'expires=${created + 300}', 'expires=${created + 301}'),
              ),
          'leading space': () => parseSigned(signed, input: ' ${signed.input}'),
          'empty input': () => parseSigned(signed, input: ''),
          'short digest': () => parseSigned(signed, digest: shortDigest),
          'wrong digest algorithm': () => parseSigned(
                signed,
                digest: signed.digest.replaceFirst('sha-256', 'sha-512'),
              ),
          'short signature': () =>
              parseSigned(signed, signature: shortSignature),
          'noncanonical audience': () =>
              parseSigned(signed, audience: '%40collector'),
          'noncanonical keyid': () => parseSigned(
                signed,
                input: signed.input.replaceFirst('"@alice"', '"%40alice"'),
              ),
        };

        for (final MapEntry<String, AtTelemetryHttpSignature Function()> entry
            in invalid.entries) {
          expect(entry.value, throwsFormatException, reason: entry.key);
        }
      });

      test('throws ArgumentError for invalid percent-encoding', () async {
        final AtTelemetryHttpSignature signed = await signHello();

        expect(
          () => parseSigned(signed, audience: '@col%ZZ'),
          throwsArgumentError,
        );
      });
    });

    group('isFresh', () {
      late AtTelemetryHttpSignature signed;

      setUp(() async {
        signed = await signHello();
      });

      test('allows created up to 30 seconds in the future', () {
        expect(signed.isFresh(secondsAfterCreated(-30)), isTrue);
        expect(signed.isFresh(secondsAfterCreated(-31)), isFalse);
      });

      test('is fresh until expires', () {
        expect(signed.isFresh(secondsAfterCreated(0)), isTrue);
        expect(signed.isFresh(secondsAfterCreated(299)), isTrue);
        expect(signed.isFresh(secondsAfterCreated(300)), isFalse);
      });

      test('converts a local time to UTC', () {
        expect(signed.isFresh(secondsAfterCreated(10).toLocal()), isTrue);
      });
    });

    group('matchesBody', () {
      test('matches only the signed body', () async {
        final AtTelemetryHttpSignature signed = await signHello();
        final List<int> changed = List<int>.of(body)..[0] ^= 1;

        expect(signed.matchesBody(body), isTrue);
        expect(signed.matchesBody(changed), isFalse);
        expect(signed.matchesBody(<int>[]), isFalse);
      });

      test('matches an empty body', () async {
        final AtTelemetryHttpSignature signed =
            await AtTelemetryHttpSignature.sign(
          body: <int>[],
          path: path,
          keyId: keyId,
          audience: audience,
          signer: signer,
        );

        expect(signed.matchesBody(<int>[]), isTrue);
      });
    });

    group('digestOf', () {
      test('is the RFC 9530 sha-256 digest', () {
        expect(
          AtTelemetryHttpSignature.digestOf(<int>[]),
          'sha-256=:47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=:',
        );
      });
    });

    group('signatureBase', () {
      test('rejects an unsafe path', () {
        for (final String unsafe in <String>[
          'v1/logs',
          '/v1/logs\n',
          '/v1/logs\r',
        ]) {
          expect(
            () => AtTelemetryHttpSignature.signatureBase(
              path: unsafe,
              digest: 'digest',
              audience: audience,
              input: input,
            ),
            throwsFormatException,
            reason: unsafe,
          );
        }
      });
    });

    group('Atsign encoding', () {
      test('round trips Atsigns', () {
        for (final String atsign in <String>[
          '@alice',
          '@alice bob',
          '@élan',
          '@🦄',
        ]) {
          final String encoded = AtTelemetryHttpSignature.encodeAtsign(atsign);
          expect(encoded, isNot(contains(' ')));
          expect(AtTelemetryHttpSignature.decodeAtsign(encoded), atsign);
        }
      });

      test('keeps @ unescaped', () {
        expect(AtTelemetryHttpSignature.encodeAtsign('@alice'), '@alice');
      });

      test('rejects a noncanonical encoding', () {
        expect(
          () => AtTelemetryHttpSignature.decodeAtsign('%40alice'),
          throwsFormatException,
        );
      });
    });
  });
}
