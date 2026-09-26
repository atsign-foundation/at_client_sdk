import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:crypto/crypto.dart';

final class AtTelemetryRsaSigner {
  final Uint8List _secretKey;

  AtTelemetryRsaSigner.fromBase64(String privateKey)
      : _secretKey = base64Decode(privateKey);

  Future<Uint8List> sign(List<int> message) =>
      RsaSignatureAlgo.rsa2048().signBytes(
        Uint8List.fromList(message),
        secretKey: _secretKey,
      );
}

final class AtTelemetryHttpSignature {
  static const String digestHeader = 'content-digest';
  static const String audienceHeader = 'at-telemetry-audience';
  static const String inputHeader = 'signature-input';
  static const String signatureHeader = 'signature';
  static const String contentType = 'application/x-protobuf';
  static const String serverIdAttribute = 'atsign.server.id';
  static const String _components =
      '("@method" "@path" "content-type" "content-digest" '
      '"at-telemetry-audience")';
  static final RegExp _inputPattern = RegExp(
    '^at=${RegExp.escape(_components)};created=([0-9]+);expires=([0-9]+);'
    'nonce="([A-Za-z0-9_-]{22})";keyid="([^"\\s]+)";'
    'alg="rsa-v1_5-sha256";tag="at-telemetry-v1"\$',
  );
  static final RegExp _digestPattern =
      RegExp(r'^sha-256=:([A-Za-z0-9+/]{43}=):$');
  static final RegExp _signaturePattern =
      RegExp(r'^at=:([A-Za-z0-9+/]{342}==):$');

  final String keyId;
  final int created;
  final int expires;
  final String nonce;
  final String input;
  final String audience;
  final String digest;
  final String signature;

  const AtTelemetryHttpSignature._({
    required this.keyId,
    required this.created,
    required this.expires,
    required this.nonce,
    required this.input,
    required this.audience,
    required this.digest,
    required this.signature,
  });

  static String encodeAtsign(String atsign) =>
      Uri.encodeComponent(atsign).replaceAll('%40', '@');

  static String decodeAtsign(String encoded) {
    final String atsign = Uri.decodeComponent(encoded);
    if (encodeAtsign(atsign) != encoded) {
      throw const FormatException('Noncanonical Atsign encoding');
    }
    return atsign;
  }

  static String digestOf(List<int> body) =>
      'sha-256=:${base64Encode(sha256.convert(body).bytes)}:';

  static String signatureBase({
    required String path,
    required String digest,
    required String audience,
    required String input,
  }) {
    if (!path.startsWith('/') || path.contains('\n') || path.contains('\r')) {
      throw const FormatException('Invalid signed path');
    }
    return '"@method": POST\n'
        '"@path": $path\n'
        '"content-type": $contentType\n'
        '"content-digest": $digest\n'
        '"at-telemetry-audience": $audience\n'
        '"@signature-params": ${input.substring(3)}';
  }

  static Future<AtTelemetryHttpSignature> sign({
    required List<int> body,
    required String path,
    required String keyId,
    required String audience,
    required AtTelemetryRsaSigner signer,
    DateTime Function()? now,
    Random? random,
  }) async {
    final int created =
        (now ?? DateTime.now)().toUtc().millisecondsSinceEpoch ~/ 1000;
    final int expires = created + 300;
    final Random source = random ?? Random.secure();
    final String nonce = base64UrlEncode(
      List<int>.generate(16, (_) => source.nextInt(256)),
    ).replaceAll('=', '');
    final String encodedId = encodeAtsign(keyId);
    final String encodedAudience = encodeAtsign(audience);
    final String digest = digestOf(body);
    final String input = 'at=$_components;created=$created;expires=$expires;'
        'nonce="$nonce";keyid="$encodedId";alg="rsa-v1_5-sha256";'
        'tag="at-telemetry-v1"';
    final String base = signatureBase(
      path: path,
      digest: digest,
      audience: encodedAudience,
      input: input,
    );
    final Uint8List bytes = await signer.sign(utf8.encode(base));
    return AtTelemetryHttpSignature._(
      keyId: keyId,
      created: created,
      expires: expires,
      nonce: nonce,
      input: input,
      audience: encodedAudience,
      digest: digest,
      signature: 'at=:${base64Encode(bytes)}:',
    );
  }

  static AtTelemetryHttpSignature parse({
    required String input,
    required String signature,
    required String digest,
    required String audience,
  }) {
    final RegExpMatch? match = _inputPattern.firstMatch(input);
    final RegExpMatch? signed = _signaturePattern.firstMatch(signature);
    final RegExpMatch? hashed = _digestPattern.firstMatch(digest);
    if (match == null || signed == null || hashed == null) {
      throw const FormatException('Invalid telemetry signature headers');
    }
    final int created = int.parse(match[1]!);
    final int expires = int.parse(match[2]!);
    if (expires <= created ||
        expires - created > 300 ||
        base64Decode(base64Url.normalize(match[3]!)).length != 16) {
      throw const FormatException('Invalid telemetry signature parameters');
    }
    final String keyId = decodeAtsign(match[4]!);
    decodeAtsign(audience);
    if (base64Decode(hashed[1]!).length != 32 ||
        base64Decode(signed[1]!).length != 256) {
      throw const FormatException('Invalid telemetry signature size');
    }
    return AtTelemetryHttpSignature._(
      keyId: keyId,
      created: created,
      expires: expires,
      nonce: match[3]!,
      input: input,
      audience: audience,
      digest: digest,
      signature: signature,
    );
  }

  bool isFresh(DateTime now) {
    final int seconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    return created <= seconds + 30 &&
        created >= seconds - 300 &&
        expires > seconds;
  }

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

  Future<bool> verify({required String path, required String publicKey}) async {
    try {
      return await RsaSignatureAlgo.rsa2048().verifyBytes(
        Uint8List.fromList(utf8.encode(signatureBase(
          path: path,
          digest: digest,
          audience: audience,
          input: input,
        ))),
        signature: base64Decode(_signaturePattern.firstMatch(signature)![1]!),
        publicKey: base64Decode(publicKey),
      );
    } on Object {
      return false;
    }
  }
}
