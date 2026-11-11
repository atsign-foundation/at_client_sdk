import 'dart:convert' show base64Decode, base64Url, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, RsaSignatureAlgo, SigningAlgoType;
import 'package:at_client/at_client_mixins.dart' show AtClientEnvelopeSigner;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys, SignedEnvelope, apskUri;
import 'package:at_commons/atsign.dart' show AtsignString;

import 'link_fixtures.dart' show withSigningKey;
import 'mocks.dart' show MockAtClient;
import 'remote_backed_client.dart' show buildRemoteBackedMockClient;

/// A client of [atSign]'s enrollment [enrollmentId] over [remoteData], holding
/// one active client data signing key under [alg] and publishing its `_apsk`
/// there.
typedef SigningClient = ({
  MockAtClient client,
  AtClientEnvelopeSigner signer,
  ApkamSigningKeys key,
  String apsk,
});

/// Builds a [SigningClient].
Future<SigningClient> signingClient(
  String atSign,
  String enrollmentId,
  Map<String, String> remoteData, {
  SigningAlgoType alg = SigningAlgoType.mldsa65,
}) async {
  final client = buildRemoteBackedMockClient(
      atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData);
  final key = await withSigningKey(client, alg: alg);
  return (
    client: client,
    signer: AtClientEnvelopeSigner(client, publicKeyCacheSettings: null),
    key: key,
    apsk: remoteData[apskUri(atSign.toAtsign(), enrollmentId)]!,
  );
}

/// A client of [atSign]'s enrollment [enrollmentId] over [remoteData] that
/// holds no key of its own, for reading what others published.
AtClientEnvelopeSigner readerOf(
        String atSign, String enrollmentId, Map<String, String> remoteData) =>
    AtClientEnvelopeSigner(
        buildRemoteBackedMockClient(
            atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData),
        publicKeyCacheSettings: null);

/// [envelope] with each protected header passed through [edit] and signed
/// again, over the same payload text, by whichever of [keys] its kid names.
SignedEnvelope resigned(
  SignedEnvelope envelope,
  List<ApkamSigningKeys> keys,
  Map<String, Object?> Function(Map<String, Object?> header) edit,
) =>
    SignedEnvelope.fromJson({
      'payload': envelope.payloadB64,
      'signatures': [
        for (final entry in envelope.signatures)
          _signed(
              edit({...entry.header}),
              envelope.payloadB64,
              keys.firstWhere((k) =>
                  entry.alg ==
                  (k.algorithm == SigningAlgoType.rsa2048
                      ? 'RS256'
                      : 'ML-DSA-65'))),
      ],
    });

/// [envelope] as at_client 4.0.0 signed it: every protected header without
/// `iss`, the remaining members in their order.
SignedEnvelope claimless(
        SignedEnvelope envelope, List<ApkamSigningKeys> keys) =>
    resigned(envelope, keys, (header) => header..remove('iss'));

Map<String, String> _signed(
    Map<String, Object?> header, String payloadB64, ApkamSigningKeys key) {
  final protected = _b64u(utf8.encode(jsonEncode(header)));
  final input = Uint8List.fromList(utf8.encode('$protected.$payloadB64'));
  final secret = base64Decode(key.privateKey);
  final signature = key.algorithm == SigningAlgoType.rsa2048
      ? RsaSignatureAlgo.rsa2048().signBytesSync(input, secretKey: secret)
      : MlDsa65PureDartAlgo.signBytesSync(input, secretKey: secret);
  return {'protected': protected, 'signature': _b64u(signature)};
}

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
