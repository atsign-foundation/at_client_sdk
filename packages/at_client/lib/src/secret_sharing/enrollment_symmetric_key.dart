import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysMaterial, CryptographicKeyType, KeyAlgorithmType;
import 'package:at_chops/at_chops.dart' show XWingPureDartAlgo, pqOpen;
import 'package:at_commons/at_builders.dart' show ScanVerbBuilder;
import 'package:at_commons/at_commons.dart'
    show AtSigningVerificationException;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_envelope.dart'
    show SecretEnvelope;
import 'package:at_client/src/signing/envelope_signature.dart'
    show verifyEnvelope;
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// The reserved [Secret] name under which an approver conveys a new
/// enrollment's `apkamSymmetricKey`.
///
/// Namespaced into the substrate's reserved space rather than an app's, so it
/// can never collide with a secret an application shares.
@experimental
const String enrollmentApkamSymmetricKeySecretName = '__apkamSymmetricKey';

final AtSignLogger _logger = AtSignLogger('EnrollmentSymmetricKey');

/// Collects the `apkamSymmetricKey` an approver encapsulated to this
/// enrollment's key package.
///
/// Pass the result to `AtEnrollmentRequest.apkamSymmetricKeyResolver` whenever
/// the request uses `EnrollmentKeyExchangeMode.pq`. It runs inside
/// `waitForApproval`, once PKAM authentication has succeeded — which is both
/// the earliest moment this enrollment can read anything and the earliest the
/// approver could have written it.
///
/// Deliberately built on [AtLookUp] rather than an `AtClient`: at this point in
/// enrollment there is no client and cannot be one, because a client is
/// constructed *from* the keys this call is fetching the last piece of.
///
/// Two things authenticate the result, and neither is optional:
///
/// - the envelope is `pqSeal`ed to this enrollment's key package, whose private
///   half was minted before the request was sent and has never left this
///   device, so nobody else can open it;
/// - the envelope carries an APKAM signature over the whole of itself, checked
///   against the signing enrollment's published `_apsk`. Without it, anyone who
///   read the (public) key package could seal a symmetric key of their choosing
///   to this enrollment and watch it unwrap its own encryption private key into
///   garbage.
@experimental
Future<String> Function(AtKeys, AtLookUp) enrollmentApkamSymmetricKeyResolver(
  String atSign, {
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(seconds: 2),
}) {
  return (AtKeys keys, AtLookUp atLookUp) async {
    final (kpid, seed) = _keyPackageHalves(keys);

    // The approver writes the envelope after the atServer has approved the
    // enrollment, and this enrollment's PKAM can start succeeding the instant
    // that approval lands — so arriving here before the envelope exists is
    // ordinary, not an error. Poll rather than fail on the first empty scan.
    final DateTime deadline = DateTime.now().toUtc().add(timeout);
    while (true) {
      for (final envelopeKey in await _envelopeKeys(atLookUp, kpid)) {
        final String? value =
            await _openIfSymmetricKey(atLookUp, envelopeKey, atSign, kpid, seed);
        if (value != null) {
          _logger.info('Collected the conveyed apkamSymmetricKey from '
              '$envelopeKey');
          return value;
        }
      }
      if (DateTime.now().toUtc().isAfter(deadline)) {
        throw StateError(
            'No conveyed apkamSymmetricKey arrived for key package $kpid '
            'within $timeout. The enrollment is approved but cannot decrypt '
            'anything without it — the approver is running a client that does '
            'not convey, or the envelope did not reach this atServer.');
      }
      await Future<void>.delayed(pollInterval);
    }
  };
}

/// This enrollment's key-package id and the X-Wing secret key that opens
/// anything sealed to it.
(String, Uint8List) _keyPackageHalves(AtKeys keys) {
  final AtKeysMaterial? private = keys.keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateDecapsulation &&
          m.keyAlgorithmType == KeyAlgorithmType.xWing)
      .firstOrNull;
  if (private == null) {
    throw StateError(
        'These AtKeys hold no X-Wing decapsulation private key, so nothing '
        'sealed to this enrollment could be opened. A pq enrollment request '
        'must have advertised a key package built by '
        'enrollmentKeyPackageBuilder, which files both halves here.');
  }
  return (private.keyId, Uint8List.fromList(private.bytes.bytes));
}

/// Every envelope key addressed to [kpid], across every namespace this
/// enrollment can see.
///
/// A scan rather than a direct lookup because the envelope's name carries a
/// random uuid — the approver chooses the address, and the only part of it
/// this side knows in advance is its own kpid.
Future<List<String>> _envelopeKeys(AtLookUp atLookUp, String kpid) async {
  final builder = ScanVerbBuilder()
    ..regex = '\\.$kpid\\.${PairwiseSecretSharing.envelopeKeyMarker}\\.';
  try {
    final String? response =
        await atLookUp.executeCommand(builder.buildCommand(), auth: true);
    if (response == null) return const [];
    final decoded =
        jsonDecode(response.replaceFirst(RegExp('^data:'), '')) as List;
    return decoded.cast<String>();
  } catch (e) {
    // A scan that fails is indistinguishable from one that finds nothing, and
    // the caller polls either way; failing the enrollment on a transient
    // atServer error would be the worse outcome.
    _logger.info('Scan for envelopes addressed to $kpid failed: $e');
    return const [];
  }
}

/// Opens [envelopeKey] and returns the conveyed symmetric key, or null if this
/// envelope is not one.
///
/// Every rejection is a skip rather than a throw: an atSign's clients may have
/// several envelopes in flight, and one that this enrollment cannot use says
/// nothing about the one it is waiting for.
Future<String?> _openIfSymmetricKey(
  AtLookUp atLookUp,
  String envelopeKey,
  String atSign,
  String kpid,
  Uint8List seed,
) async {
  final Map signedEnvelope;
  try {
    final String? raw =
        await atLookUp.executeCommand('llookup:$envelopeKey\n', auth: true);
    if (raw == null) return null;
    signedEnvelope =
        jsonDecode(raw.replaceFirst(RegExp('^data:'), '')) as Map;
  } catch (e) {
    _logger.info('Could not read envelope $envelopeKey: $e');
    return null;
  }

  // Verify FIRST: the seal authenticates the payload bytes, but only the
  // APKAM signature authenticates who sent them.
  try {
    await _verifyAgainstApsk(atLookUp, signedEnvelope, atSign);
  } on AtSigningVerificationException catch (e) {
    _logger.warning('Envelope $envelopeKey failed signature verification, so '
        'it is not from an approved enrollment of $atSign; skipping: $e');
    return null;
  }

  final SecretEnvelope envelope;
  try {
    envelope = SecretEnvelope.fromJson(signedEnvelope['payload']);
  } catch (e) {
    _logger.warning('Envelope $envelopeKey is malformed; skipping: $e');
    return null;
  }

  if (envelope.toKpid != kpid ||
      signedEnvelope['enrollmentId'] != envelope.fromEnrollmentId ||
      !SecretSharingAlgos.suites.contains(envelope.suite)) {
    return null;
  }

  final Uint8List plaintext;
  try {
    plaintext = await pqOpen(
      XWingPureDartAlgo.instance,
      seed,
      base64Decode(envelope.sealed),
      info: PairwiseSecretSharing.sealInfo,
    );
  } catch (e) {
    _logger.warning('Envelope $envelopeKey failed to open; skipping: $e');
    return null;
  }

  final payload = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  if (payload['kind'] != PairwiseSecretSharing.secretPayloadKind ||
      payload['name'] != enrollmentApkamSymmetricKeySecretName) {
    return null;
  }
  return payload['value'] as String;
}

/// Checks the envelope's APKAM signature against the `_apsk` the atServer
/// published for the signing enrollment.
///
/// A revoked enrollment's `_apsk` has been moved out from under this address
/// by the atServer, so the lookup finds nothing and verification fails — which
/// is the intended outcome, and the reason no separate revocation check is
/// needed here.
Future<void> _verifyAgainstApsk(
  AtLookUp atLookUp,
  Map signedEnvelope,
  String atSign,
) async {
  final claimed = signedEnvelope['enrollmentId'];
  if (claimed is! String || claimed.isEmpty) {
    throw AtSigningVerificationException(
        'Envelope names no enrollment, so there is no _apsk to check its '
        'signature against');
  }
  final String? response = await atLookUp.executeCommand(
      'llookup:public:_apsk.$claimed.a.__e$atSign\n',
      auth: true);
  final String? publicKey = response?.replaceFirst(RegExp('^data:'), '').trim();
  if (publicKey == null || publicKey.isEmpty) {
    throw AtSigningVerificationException(
        'No _apsk published for $atSign enrollment $claimed, so its signature '
        'cannot be checked');
  }
  verifyEnvelope(signedEnvelope, signerPublicKey: publicKey);
}
