import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../codecs/at_telemetry_logs_codec.dart';
import '../signers/at_telemetry_ed25519_signer.dart';
import '../signers/at_telemetry_signer.dart';
import 'at_telemetry_sequence.dart';

// The at-telemetry-v1 profile of an RFC 9421 HTTP message signature. It covers
// the method, path, content type, body digest, audience, producer and
// sequence, so a signature binds the body to one collector, one atServer and
// one place in that atServer's stream.
final class AtTelemetryHttpSignature {
  static const String tag = 'at-telemetry-v1';
  static const String method = 'POST';
  static const String contentType = AtTelemetryLogsCodec.contentType;
  static const String contentTypeHeader = 'content-type';
  static const String digestHeader = 'content-digest';
  static const String audienceHeader = 'at-telemetry-audience';
  static const String producerHeader = 'at-telemetry-producer';
  static const String sequenceHeader = 'at-telemetry-sequence';
  static const String inputHeader = 'signature-input';
  static const String signatureHeader = 'signature';
  static const int maxLifetimeSeconds = 300;
  static const int maxClockSkewSeconds = 30;
  static const String _components =
      '("@method" "@path" "content-type" "content-digest" '
      '"at-telemetry-audience" "at-telemetry-producer" '
      '"at-telemetry-sequence")';
  static final RegExp _inputPattern = RegExp(
    '^at=${RegExp.escape(_components)};'
    'created=([0-9]{1,12});expires=([0-9]{1,12});'
    'keyid="([A-Za-z0-9_-]{16})";alg="([a-z0-9-]{1,32})";'
    'tag="${RegExp.escape(tag)}"\$',
  );
  static final RegExp _digestPattern =
      RegExp(r'^sha-256=:([A-Za-z0-9+/]{43}=):$');
  static final RegExp _signaturePattern =
      RegExp(r'^at=:([A-Za-z0-9+/]{4,8192}={0,2}):$');
  static final RegExp _audiencePattern =
      RegExp(r'^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?(:[0-9]{1,5})?$');

  final String keyId;
  final String algorithm;
  final int created;
  final int expires;
  final String audience;
  final String producer;
  final AtTelemetrySequence sequence;
  final String input;
  final String digest;
  final String signature;

  const AtTelemetryHttpSignature._({
    required this.keyId,
    required this.algorithm,
    required this.created,
    required this.expires,
    required this.audience,
    required this.producer,
    required this.sequence,
    required this.input,
    required this.digest,
    required this.signature,
  });

  // Percent-encodes everything but the @, so an atSign with emoji fits in a
  // header
  static String encodeAtsign(String atsign) =>
      Uri.encodeComponent(atsign).replaceAll('%40', '@');

  static String decodeAtsign(String encoded) {
    final String atsign;
    try {
      atsign = Uri.decodeComponent(encoded);
    } on ArgumentError {
      throw const FormatException('Invalid atSign encoding');
    }
    if (encodeAtsign(atsign) != encoded ||
        !atsign.startsWith('@') ||
        atsign.length < 2) {
      throw const FormatException('Noncanonical atSign encoding');
    }
    return atsign;
  }

  static String digestOf(List<int> body) =>
      'sha-256=:${base64Encode(sha256.convert(body).bytes)}:';

  static String signatureBase({
    required String path,
    required String digest,
    required String audience,
    required String producer,
    required AtTelemetrySequence sequence,
    required String input,
  }) {
    if (!path.startsWith('/') ||
        path.contains(RegExp(r'[\s]')) ||
        !input.startsWith('at=')) {
      throw const FormatException('Invalid signed path or input');
    }
    return '"@method": $method\n'
        '"@path": $path\n'
        '"$contentTypeHeader": $contentType\n'
        '"$digestHeader": $digest\n'
        '"$audienceHeader": $audience\n'
        '"$producerHeader": ${encodeAtsign(producer)}\n'
        '"$sequenceHeader": ${sequence.header}\n'
        '"@signature-params": ${input.substring(3)}';
  }

  static Future<AtTelemetryHttpSignature> sign({
    required List<int> body,
    required String path,
    required String keyId,
    required String audience,
    required String producer,
    required AtTelemetrySequence sequence,
    required AtTelemetrySigner signer,
    DateTime Function()? now,
  }) async {
    if (!_audiencePattern.hasMatch(audience)) {
      throw ArgumentError.value(audience, 'audience', 'must be a host');
    }
    if (!producer.startsWith('@') || producer.length < 2) {
      throw ArgumentError.value(producer, 'producer', 'must be an atSign');
    }
    final int created =
        (now ?? DateTime.now)().toUtc().millisecondsSinceEpoch ~/ 1000;
    final int expires = created + maxLifetimeSeconds;
    final String digest = digestOf(body);
    final String input = 'at=$_components;created=$created;expires=$expires;'
        'keyid="$keyId";alg="${signer.algorithm}";tag="$tag"';
    if (!_inputPattern.hasMatch(input)) {
      throw ArgumentError.value(keyId, 'keyId', 'is not a telemetry key id');
    }
    final String base = signatureBase(
      path: path,
      digest: digest,
      audience: audience,
      producer: producer,
      sequence: sequence,
      input: input,
    );
    final Uint8List bytes = await signer.sign(utf8.encode(base));
    return AtTelemetryHttpSignature._(
      keyId: keyId,
      algorithm: signer.algorithm,
      created: created,
      expires: expires,
      audience: audience,
      producer: producer,
      sequence: sequence,
      input: input,
      digest: digest,
      signature: 'at=:${base64Encode(bytes)}:',
    );
  }

  // Checks the headers' shapes only. The caller still checks freshness, the
  // audience, the body digest and the signature itself.
  static AtTelemetryHttpSignature parse({
    required String input,
    required String signature,
    required String digest,
    required String audience,
    required String producer,
    required String sequence,
  }) {
    final RegExpMatch? match = _inputPattern.firstMatch(input);
    final RegExpMatch? signed = _signaturePattern.firstMatch(signature);
    final RegExpMatch? hashed = _digestPattern.firstMatch(digest);
    if (match == null ||
        signed == null ||
        hashed == null ||
        !_audiencePattern.hasMatch(audience)) {
      throw const FormatException('Invalid telemetry signature headers');
    }
    final int created = int.parse(match[1]!);
    final int expires = int.parse(match[2]!);
    if (expires <= created || expires - created > maxLifetimeSeconds) {
      throw const FormatException('Invalid telemetry signature lifetime');
    }
    final String algorithm = match[4]!;
    final Uint8List signatureBytes;
    try {
      signatureBytes = base64Decode(signed[1]!);
    } on FormatException {
      throw const FormatException('Invalid telemetry signature encoding');
    }
    if (base64Decode(hashed[1]!).length != 32 ||
        (algorithm == AtTelemetryEd25519Signer.algorithmName &&
            signatureBytes.length !=
                AtTelemetryEd25519Signer.signatureLength)) {
      throw const FormatException('Invalid telemetry signature size');
    }
    return AtTelemetryHttpSignature._(
      keyId: match[3]!,
      algorithm: algorithm,
      created: created,
      expires: expires,
      audience: audience,
      producer: decodeAtsign(producer),
      sequence: AtTelemetrySequence.parse(sequence),
      input: input,
      digest: digest,
      signature: signature,
    );
  }

  Map<String, String> get headers => <String, String>{
        contentTypeHeader: contentType,
        digestHeader: digest,
        audienceHeader: audience,
        producerHeader: encodeAtsign(producer),
        sequenceHeader: sequence.header,
        inputHeader: input,
        signatureHeader: signature,
      };

  bool isFresh(DateTime now) {
    final int seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    return created <= seconds + maxClockSkewSeconds &&
        created >= seconds - maxLifetimeSeconds &&
        expires > seconds;
  }

  // Constant time, so the comparison leaks nothing about the expected digest
  bool matchesBody(List<int> body) {
    final List<int> expected =
        base64Decode(_digestPattern.firstMatch(digest)![1]!);
    final List<int> actual = sha256.convert(body).bytes;
    int difference = 0;
    for (int index = 0; index < expected.length; index++) {
      difference |= expected[index] ^ actual[index];
    }
    return difference == 0;
  }

  Future<bool> verify({
    required String path,
    required List<int> publicKey,
  }) async {
    if (algorithm != AtTelemetryEd25519Signer.algorithmName) {
      return false;
    }
    try {
      return await AtTelemetryEd25519Signer.verify(
        message: utf8.encode(signatureBase(
          path: path,
          digest: digest,
          audience: audience,
          producer: producer,
          sequence: sequence,
          input: input,
        )),
        signature: base64Decode(_signaturePattern.firstMatch(signature)![1]!),
        publicKey: publicKey,
      );
    } on Object {
      return false;
    }
  }
}
