import 'dart:convert';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart'
    show AtKeys, AtKeysMaterial, CryptographicKeyType;
import 'package:at_chops/at_chops.dart' show AtKemAlgorithm, pqOpen;
import 'package:at_commons/at_builders.dart' show ScanVerbBuilder;
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/envelope_addressing.dart'
    show EnvelopeAddressing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_client/src/secret_sharing/secret_envelope.dart'
    show SecretEnvelope;
import 'package:at_client/src/signing/envelope_signature.dart'
    show apskUri, SignedEnvelope, verifyEnvelope;
import 'package:at_lookup/at_lookup.dart' show AtLookUp;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// The reserved [Secret] name under which an approver conveys a new
/// enrollment's `apkamSymmetricKey`.
///
/// Carries the per-enrollment prefix, so it is never forwarded to the next
/// enrollment this one approves — it is addressed to exactly one device.
@experimental
const String enrollmentApkamSymmetricKeySecretName =
    '${PairwiseSecretSharing.perEnrollmentSecretPrefix}apkamSymmetricKey';

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
    final (kpid, secretKey, keyAlgo) = await _keyPackageHalves(keys);

    // This never waits for the human. By the time it runs, waitForApproval's
    // PKAM loop has already succeeded, which means the approval has happened —
    // however many minutes or hours that took is behind us.
    //
    // What is left is a mechanical race inside the approver's single approve()
    // call: the atServer marks the enrollment approved, which is what lets
    // PKAM start succeeding, a moment before at_client finishes writing the
    // envelope. That is one or two round trips, so arriving here before the
    // envelope exists is ordinary rather than an error. [timeout] is headroom
    // over that race, not a latency budget — if nothing has arrived by then
    // the approver did not convey, and waiting longer recovers nothing.
    final DateTime deadline = DateTime.now().toUtc().add(timeout);
    while (true) {
      for (final envelopeKey in await _envelopeKeys(atLookUp, kpid)) {
        final String? value = await _openIfSymmetricKey(
            atLookUp, envelopeKey, atSign, kpid, secretKey, keyAlgo);
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

/// This enrollment's key-package id, the decapsulation key that opens anything
/// sealed to it, and which KEM that key belongs to.
///
/// The keyfile stores the **seed**, not the decapsulation key: they are the
/// same bytes for X-Wing but not for ML-KEM, whose decapsulation key is
/// expanded and which no seeded call reproduces from. So the seed is expanded
/// here, once, rather than handed to `pqOpen` as if it were the key.
Future<(String, Uint8List, String)> _keyPackageHalves(AtKeys keys) async {
  final AtKeysMaterial? private = keys.keys
      .where((m) =>
          m.keyPartType == CryptographicKeyType.privateDecapsulation &&
          SecretSharingAlgos.keyAlgoForMaterial(m.keyAlgorithmType) != null)
      .firstOrNull;
  if (private == null) {
    throw StateError(
        'These AtKeys hold no key-establishment decapsulation private key, so '
        'nothing sealed to this enrollment could be opened. A pq enrollment '
        'request must have advertised a key package built by '
        'enrollmentKeyPackageBuilder, which files both halves here. '
        'Supported: ${SecretSharingAlgos.keyAlgos}');
  }
  final keyAlgo =
      SecretSharingAlgos.keyAlgoForMaterial(private.keyAlgorithmType)!;
  final pair = await SecretSharingAlgos.kemFor(keyAlgo)!
      .keyPairFromSeed(Uint8List.fromList(private.bytes.bytes));
  return (private.keyId, pair.secretKey, keyAlgo);
}

/// Every envelope key addressed to [kpid], across every namespace this
/// enrollment can see.
///
/// A scan rather than a direct lookup because the envelope's name carries a
/// random uuid — the approver chooses the address, and the only part of it
/// this side knows in advance is its own kpid.
Future<List<String>> _envelopeKeys(AtLookUp atLookUp, String kpid) async {
  final builder = ScanVerbBuilder()
    ..regex = EnvelopeAddressing.regexFor(kpid);
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
  Uint8List secretKey,
  String keyAlgo,
) async {
  final SignedEnvelope signedEnvelope;
  try {
    final String? raw =
        await atLookUp.executeCommand('llookup:$envelopeKey\n', auth: true);
    if (raw == null) return null;
    signedEnvelope = SignedEnvelope.fromJson(
        jsonDecode(raw.replaceFirst(RegExp('^data:'), '')) as Map);
  } catch (e) {
    _logger.info('Could not read envelope $envelopeKey: $e');
    return null;
  }

  // Verify FIRST: the seal authenticates the payload bytes, but only the
  // APKAM signature authenticates who sent them.
  try {
    await _verifyAgainstApsk(atLookUp, signedEnvelope, atSign);
  } catch (e) {
    // Every way this can fail is a reason to skip THIS envelope, and none of
    // them is a reason to fail the enrollment. The typed refusal is only one
    // of them: an absent `_apsk` arrives as a thrown AT0015, and a malformed
    // one throws a FormatException out of base64 — both from the same single
    // operation, verifying this envelope's signature, and both previously
    // escaping to kill the whole approval. A revoked enrollment produces the
    // first, so one stale envelope of its making would fail every later
    // enrollment that scanned past it.
    _logger.warning('Envelope $envelopeKey failed signature verification, so '
        'it is not from an approved enrollment of $atSign; skipping: $e');
    return null;
  }

  final SecretEnvelope envelope;
  try {
    envelope = SecretEnvelope.fromJson(signedEnvelope.payload);
  } catch (e) {
    _logger.warning('Envelope $envelopeKey is malformed; skipping: $e');
    return null;
  }

  // The suite names the KEM, and resolving it is also the support check —
  // a separate membership test against `SecretSharingAlgos.suites` would be a
  // second list that has to agree with this one.
  final AtKemAlgorithm? kem = SecretSharingAlgos.kemForSuite(envelope.suite);
  if (envelope.toKpid != kpid ||
      signedEnvelope.signerEnrollmentId != envelope.fromEnrollmentId ||
      kem == null ||
      // The suite's KEM must be the one this key package's key belongs to.
      // A sender that picked the other one produced something [secretKey]
      // cannot decapsulate, and passing it to pqOpen anyway would report an
      // AEAD failure rather than the addressing mistake it is.
      !identical(kem, SecretSharingAlgos.kemFor(keyAlgo))) {
    return null;
  }

  final Uint8List plaintext;
  try {
    plaintext = await pqOpen(
      kem,
      secretKey,
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
/// by the atServer, so the lookup fails and with it the verification — which is
/// the intended outcome, and the reason no separate revocation check is needed
/// here. It fails by **throwing**, not by returning null, which is why the
/// caller's skip has to catch more than the typed refusal.
Future<void> _verifyAgainstApsk(
  AtLookUp atLookUp,
  SignedEnvelope signedEnvelope,
  String atSign,
) async {
  final claimed = signedEnvelope.signerEnrollmentId;
  if (claimed == null || claimed.isEmpty) {
    throw AtSigningVerificationException(
        'Envelope names no enrollment, so there is no _apsk to check its '
        'signature against');
  }
  // An absent `_apsk` does not come back null: the atServer answers AT0015 and
  // `AtLookupImpl` throws it. That is the revoked-enrollment case this doc
  // comment describes, and the caller treats a throw from here the same way it
  // treats the refusal below — see the skip in [_openIfSymmetricKey].
  final String? response = await atLookUp
      .executeCommand('llookup:${apskUri(atSign, claimed)}\n', auth: true);
  final String? publicKey = response?.replaceFirst(RegExp('^data:'), '').trim();
  if (publicKey == null || publicKey.isEmpty) {
    throw AtSigningVerificationException(
        'No _apsk published for $atSign enrollment $claimed, so its signature '
        'cannot be checked');
  }
  await verifyEnvelope(signedEnvelope, signerPublicKey: publicKey);
}
