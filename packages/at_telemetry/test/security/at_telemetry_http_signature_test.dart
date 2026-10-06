import 'dart:convert';
import 'dart:typed_data';

import 'package:at_telemetry/at_telemetry.dart';
import 'package:test/test.dart';

import '../helpers/callback_signer.dart';

void main() {
  const String path = '/v1/logs';
  const String audience = 'collector.example.com';
  const String producer = '@producer1';
  const int created = 1790380800;
  final List<int> body = utf8.encode('{"resourceLogs":[]}');
  final AtTelemetrySequence sequence = AtTelemetrySequence(
    bootId: 'AAECAwQFBgcICQoLDA0ODw',
    number: 42,
  );

  late AtTelemetryEd25519Signer signer;
  late AtTelemetryEd25519Signer otherSigner;
  late String keyId;

  setUpAll(() async {
    signer = await AtTelemetryEd25519Signer.fromSeed(
      List<int>.generate(32, (int index) => index),
    );
    otherSigner = await AtTelemetryEd25519Signer.fromSeed(
      List<int>.generate(32, (int index) => 255 - index),
    );
    keyId = AtTelemetryPublicKeyRecord.keyIdFor(signer.publicKey);
  });

  DateTime at(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

  Future<AtTelemetryHttpSignature> signBody({
    String audience = audience,
    String producer = producer,
    AtTelemetrySigner? using,
  }) {
    return AtTelemetryHttpSignature.sign(
      body: body,
      path: path,
      keyId: keyId,
      audience: audience,
      producer: producer,
      sequence: sequence,
      signer: using ?? signer,
      now: () => at(created),
    );
  }

  AtTelemetryHttpSignature reparse(
    AtTelemetryHttpSignature signed, {
    String? input,
    String? signature,
    String? digest,
    String? audience,
    String? producer,
    String? sequence,
  }) {
    final Map<String, String> headers = signed.headers;
    return AtTelemetryHttpSignature.parse(
      input: input ?? headers[AtTelemetryHttpSignature.inputHeader]!,
      signature:
          signature ?? headers[AtTelemetryHttpSignature.signatureHeader]!,
      digest: digest ?? headers[AtTelemetryHttpSignature.digestHeader]!,
      audience: audience ?? headers[AtTelemetryHttpSignature.audienceHeader]!,
      producer: producer ?? headers[AtTelemetryHttpSignature.producerHeader]!,
      sequence: sequence ?? headers[AtTelemetryHttpSignature.sequenceHeader]!,
    );
  }

  group('AtTelemetryHttpSignature', () {
    group('sign', () {
      test('writes the at-telemetry profile headers', () async {
        final AtTelemetryHttpSignature signed = await signBody();

        expect(signed.headers, <String, String>{
          'content-type': 'application/json',
          'content-digest': AtTelemetryHttpSignature.digestOf(body),
          'at-telemetry-audience': 'collector.example.com',
          'at-telemetry-producer': '@producer1',
          'at-telemetry-sequence': 'boot=AAECAwQFBgcICQoLDA0ODw;seq=42',
          'signature-input': 'at=("@method" "@path" "content-type" '
              '"content-digest" "at-telemetry-audience" '
              '"at-telemetry-producer" "at-telemetry-sequence");'
              'created=1790380800;expires=1790381100;keyid="$keyId";'
              'alg="ed25519";tag="at-telemetry"',
          'signature': signed.signature,
        });
        expect(signed.signature, matches(r'^at=:[A-Za-z0-9+/]{86}==:$'));
      });

      test('signs exactly the RFC 9421 signature base', () async {
        final List<String> messages = <String>[];
        await signBody(
          using: CallbackSigner((List<int> message) async {
            messages.add(utf8.decode(message));
            return Uint8List(64);
          }),
        );

        expect(
          messages.single,
          '"@method": POST\n'
          '"@path": /v1/logs\n'
          '"content-type": application/json\n'
          '"content-digest": ${AtTelemetryHttpSignature.digestOf(body)}\n'
          '"at-telemetry-audience": collector.example.com\n'
          '"at-telemetry-producer": @producer1\n'
          '"at-telemetry-sequence": boot=AAECAwQFBgcICQoLDA0ODw;seq=42\n'
          '"@signature-params": ("@method" "@path" "content-type" '
          '"content-digest" "at-telemetry-audience" "at-telemetry-producer" '
          '"at-telemetry-sequence");created=1790380800;expires=1790381100;'
          'keyid="$keyId";alg="ed25519";tag="at-telemetry"',
        );
      });

      test('percent-encodes an atSign with emoji in the producer header',
          () async {
        final AtTelemetryHttpSignature signed =
            await signBody(producer: '@☎️_0002');

        expect(
          signed.headers[AtTelemetryHttpSignature.producerHeader],
          '@%E2%98%8E%EF%B8%8F_0002',
        );
        expect(reparse(signed).producer, '@☎️_0002');
      });

      test('rejects an audience that is not a host', () async {
        expect(
            () => signBody(audience: 'Collector Example'), throwsArgumentError);
        expect(() => signBody(audience: 'a\nb'), throwsArgumentError);
      });

      test('rejects a producer that is not an atSign', () async {
        expect(() => signBody(producer: 'producer1'), throwsArgumentError);
      });
    });

    group('verify', () {
      test('accepts a signature made with the matching key', () async {
        final AtTelemetryHttpSignature parsed = reparse(await signBody());

        expect(parsed.keyId, keyId);
        expect(parsed.algorithm, 'ed25519');
        expect(parsed.producer, producer);
        expect(parsed.sequence, sequence);
        expect(parsed.audience, audience);
        expect(parsed.isFresh(at(created)), isTrue);
        expect(parsed.matchesBody(body), isTrue);
        expect(
          await parsed.verify(path: path, publicKey: signer.publicKey),
          isTrue,
        );
      });

      test('rejects another key', () async {
        final AtTelemetryHttpSignature parsed = reparse(await signBody());

        expect(
          await parsed.verify(path: path, publicKey: otherSigner.publicKey),
          isFalse,
        );
      });

      test('rejects another path', () async {
        final AtTelemetryHttpSignature parsed = reparse(await signBody());

        expect(
          await parsed.verify(path: '/v1/metrics', publicKey: signer.publicKey),
          isFalse,
        );
      });

      final Map<String, Map<String, String>> tampered =
          <String, Map<String, String>>{
        'audience': <String, String>{'audience': 'other.example.com'},
        'producer': <String, String>{'producer': '@producer2'},
        'sequence': <String, String>{
          'sequence': 'boot=AAECAwQFBgcICQoLDA0ODw;seq=43',
        },
        'boot id': <String, String>{
          'sequence': 'boot=AQECAwQFBgcICQoLDA0ODw;seq=42',
        },
        'digest': <String, String>{
          'digest': AtTelemetryHttpSignature.digestOf(utf8.encode('{}')),
        },
      };
      for (final MapEntry<String, Map<String, String>> entry
          in tampered.entries) {
        test('rejects a changed ${entry.key}', () async {
          final AtTelemetryHttpSignature signed = await signBody();
          final AtTelemetryHttpSignature parsed = reparse(
            signed,
            audience: entry.value['audience'],
            producer: entry.value['producer'],
            sequence: entry.value['sequence'],
            digest: entry.value['digest'],
          );

          expect(
            await parsed.verify(path: path, publicKey: signer.publicKey),
            isFalse,
          );
        });
      }

      test('rejects an alg it does not implement', () async {
        final AtTelemetryHttpSignature signed = await signBody();
        final AtTelemetryHttpSignature parsed = reparse(
          signed,
          input: signed.input.replaceFirst('alg="ed25519"', 'alg="mldsa65"'),
        );

        expect(parsed.algorithm, 'mldsa65');
        expect(
          await parsed.verify(path: path, publicKey: signer.publicKey),
          isFalse,
        );
      });

      test('matchesBody rejects a different body', () async {
        final AtTelemetryHttpSignature parsed = reparse(await signBody());

        expect(parsed.matchesBody(utf8.encode('{}')), isFalse);
      });
    });

    group('isFresh', () {
      test('allows 30 seconds of clock skew and 300 seconds of age', () async {
        final AtTelemetryHttpSignature parsed = reparse(await signBody());

        expect(parsed.isFresh(at(created - 30)), isTrue);
        expect(parsed.isFresh(at(created - 31)), isFalse);
        expect(parsed.isFresh(at(created + 299)), isTrue);
        expect(parsed.isFresh(at(created + 300)), isFalse);
      });
    });

    group('parse', () {
      final Map<String, String Function(String)> badInputs =
          <String, String Function(String)>{
        'the old v1 tag': (String input) =>
            input.replaceFirst('tag="at-telemetry"', 'tag="at-telemetry-v1"'),
        'a nonce parameter': (String input) =>
            input.replaceFirst(';keyid=', ';nonce="abc";keyid='),
        'a missing covered component': (String input) =>
            input.replaceFirst(' "at-telemetry-sequence"', ''),
        'reordered components': (String input) => input.replaceFirst(
              '"at-telemetry-producer" "at-telemetry-sequence"',
              '"at-telemetry-sequence" "at-telemetry-producer"',
            ),
        'a lifetime over 300 seconds': (String input) =>
            input.replaceFirst('expires=1790381100', 'expires=1790381101'),
        'expires before created': (String input) =>
            input.replaceFirst('expires=1790381100', 'expires=1790380700'),
        'an atSign as keyid': (String input) =>
            input.replaceFirst(RegExp(r'keyid="[^"]+"'), 'keyid="@producer1"'),
      };
      for (final MapEntry<String, String Function(String)> entry
          in badInputs.entries) {
        test('rejects signature-input with ${entry.key}', () async {
          final AtTelemetryHttpSignature signed = await signBody();

          expect(
            () => reparse(signed, input: entry.value(signed.input)),
            throwsFormatException,
          );
        });
      }

      final Map<String, Map<String, String>> badHeaders =
          <String, Map<String, String>>{
        'a short signature': <String, String>{
          'signature': 'at=:${base64Encode(Uint8List(63))}:',
        },
        'a malformed digest': <String, String>{'digest': 'sha-256=:abc:'},
        'an audience with a space': <String, String>{
          'audience': 'collector .example.com',
        },
        'a producer without @': <String, String>{'producer': 'producer1'},
        'a noncanonical producer': <String, String>{'producer': '%40producer1'},
        'a malformed sequence': <String, String>{'sequence': 'seq=42'},
        'a sequence with a leading zero': <String, String>{
          'sequence': 'boot=AAECAwQFBgcICQoLDA0ODw;seq=042',
        },
      };
      for (final MapEntry<String, Map<String, String>> entry
          in badHeaders.entries) {
        test('rejects ${entry.key}', () async {
          final AtTelemetryHttpSignature signed = await signBody();

          expect(
            () => reparse(
              signed,
              signature: entry.value['signature'],
              digest: entry.value['digest'],
              audience: entry.value['audience'],
              producer: entry.value['producer'],
              sequence: entry.value['sequence'],
            ),
            throwsFormatException,
          );
        });
      }
    });
  });
}
