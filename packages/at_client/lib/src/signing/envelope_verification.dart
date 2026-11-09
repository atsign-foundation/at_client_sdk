/// Offline verification of application envelopes against the `_apsk` value
/// their signer's enrollment published.
library;

import 'dart:convert' show base64Decode, base64Url, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart' show ApskSigningKey, KeyEntryStatus;
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/signing/envelope_signature.dart'
    show
        EnvelopeSignature,
        EnvelopeType,
        SignedEnvelope,
        apskUri,
        canSignEnvelopeWith,
        checkEnvelopeSignature,
        envelopeVersion,
        exceedsUtf8Bytes,
        quotedClaim,
        quotedClaims,
        issuerOf,
        parseApskValue,
        readApsk,
        requireApskEnrollmentId,
        signsUnder;
import 'package:at_commons/at_commons.dart' show AtSigningVerificationException;
import 'package:at_commons/atsign.dart' show Atsign, AtsignString;
import 'package:meta/meta.dart' show experimental;

/// The longest `_apsk` value [verifySignedEnvelope] reads, in UTF-8 bytes:
/// 512 KiB.
@experimental
const int maxPublishedApskLength = 512 * 1024;

/// An `_apsk` value as [atSign]'s enrollment [enrollmentId] published it at
/// `public:_apsk.<enrollmentId>.a.__e@<atSign>`, and whose it is.
@experimental
final class PublishedApsk {
  /// Throws [InvalidAtSignException] when [atSign] is not an Atsign, and
  /// [AtSigningVerificationException] when [enrollmentId] cannot name an
  /// `_apsk`; [value] is kept verbatim and read only when used.
  PublishedApsk({
    required String atSign,
    required String enrollmentId,
    required this.value,
  })  : atSign = atSign.toAtsign(),
        enrollmentId = requireApskEnrollmentId(enrollmentId);

  /// The Atsign, canonical.
  final Atsign atSign;

  final String enrollmentId;

  /// The `_apsk` value, verbatim.
  final String value;

  /// The client data signing keys [value] lists whose status still vouches
  /// for what they signed; throws [AtSigningVerificationException] when
  /// [value] cannot be read or is longer than [maxPublishedApskLength].
  List<ApskSigningKey> get keys {
    if (exceedsUtf8Bytes(value, maxPublishedApskLength)) {
      throw AtSigningVerificationException(_oversize);
    }
    return parseApskValue(value).keys;
  }

  @override
  String toString() =>
      'PublishedApsk(${apskUri(atSign, enrollmentId)}, ${value.length} '
      'characters)';
}

const String _oversize = 'the _apsk value is longer than '
    '$maxPublishedApskLength bytes in UTF-8, the most this build reads';

/// What [verifySignedEnvelope] found.
@experimental
sealed class EnvelopeVerification {
  /// The `_apsk` the envelope was checked against.
  PublishedApsk get signer;
}

/// What [selectEnvelopeKey] found.
@experimental
sealed class EnvelopeKeySelection {
  /// The `_apsk` the envelope was checked against.
  PublishedApsk get signer;
}

/// The envelope names [signer]'s enrollment, names [signer]'s Atsign or none,
/// and its signature verifies under a key [signer] lists.
@experimental
final class EnvelopeVerified implements EnvelopeVerification {
  EnvelopeVerified._(EnvelopeKeySelected selected)
      : signer = selected.signer,
        kid = selected.kid,
        algorithm = selected.algorithm,
        keyStatus = selected.keyStatus,
        issuerConfirmed = selected.issuerConfirmed;

  @override
  final PublishedApsk signer;

  /// The key that verified.
  final String kid;

  final SigningAlgoType algorithm;

  /// The status [signer] lists the key under: active or retired.
  final KeyEntryStatus keyStatus;

  /// True when the signature covers an `iss` naming [signer]'s Atsign; false
  /// for an envelope that names none, as at_client 4.0.0 signed them.
  ///
  /// An envelope that names no Atsign verifies with this false until the
  /// release that re-signs what an enrollment publishes.
  final bool issuerConfirmed;

  @override
  String toString() => 'EnvelopeVerified(${signer.atSign}, '
      '${signer.enrollmentId}, kid: ${quotedClaim(kid)}, ${algorithm.name}, '
      '${quotedClaim(keyStatus)}, '
      'issuerConfirmed: $issuerConfirmed)';
}

/// The key [verifySignedEnvelope] would check the envelope's signature
/// against.
@experimental
final class EnvelopeKeySelected implements EnvelopeKeySelection {
  EnvelopeKeySelected._(
      this.signer, this.key, this.issuerConfirmed, this._entry);

  @override
  final PublishedApsk signer;

  /// The entry [signer] lists for the key, which says whether it is still
  /// offered for new operations.
  final ApskSigningKey key;

  /// True when the envelope's `iss` names [signer]'s Atsign; false when it
  /// names none, as at_client 4.0.0 signed them.
  final bool issuerConfirmed;

  final EnvelopeSignature _entry;

  String get kid => key.kid;

  SigningAlgoType get algorithm => key.alg;

  KeyEntryStatus get keyStatus => key.status;

  @override
  String toString() => 'EnvelopeKeySelected(${signer.atSign}, '
      '${signer.enrollmentId}, kid: ${quotedClaim(kid)}, ${algorithm.name}, '
      '${quotedClaim(keyStatus)}, '
      'issuerConfirmed: $issuerConfirmed)';
}

/// The envelope does not verify against [signer], and why.
@experimental
final class EnvelopeRefused
    implements EnvelopeVerification, EnvelopeKeySelection {
  EnvelopeRefused._(this.signer, this.refusal, this.reason, this.kid);

  @override
  final PublishedApsk signer;

  final EnvelopeRefusal refusal;

  /// One line saying why.
  final String reason;

  /// The kid the envelope's selected entry names, when one is known.
  final String? kid;

  @override
  String toString() => 'EnvelopeRefused(${refusal.name}, kid: '
      '${kid == null ? 'none' : quotedClaim(kid!)}: $reason)';
}

/// Why an envelope was refused.
@experimental
enum EnvelopeRefusal {
  /// The `_apsk` value is longer than [maxPublishedApskLength].
  oversize,

  /// The envelope cannot be read: an entry names no key, or a signature is
  /// not base64url.
  malformedEnvelope,

  /// An entry names an envelope version this build does not read.
  unsupportedVersion,

  /// The envelope was signed for something other than an application.
  wrongType,

  /// The envelope names an Atsign other than the `_apsk`'s, or a claim that
  /// is not an Atsign.
  wrongAtSign,

  /// The envelope names no enrollment, or one other than the `_apsk`'s.
  wrongEnrollment,

  /// The `_apsk` value cannot be read.
  malformedKeySet,

  /// The `_apsk` lists no key the envelope's selected entry names.
  keyNotInKeySet,

  /// The `_apsk` lists the key under a status that does not vouch for what
  /// it signed.
  keyNotVouchedFor,

  /// The strongest algorithm the envelope and the `_apsk` share is weaker
  /// than the caller's minimum.
  algorithmTooWeak,

  /// The signature does not verify.
  badSignature,
}

/// Checks that [envelope] is an application envelope that names [signer]'s
/// Atsign and enrollment and is signed with a client data signing key
/// [signer] lists, under [minimumAlgorithm] or stronger when given, without
/// an `AtClient`, the network or a clock; never throws.
///
/// An envelope that names no Atsign verifies with
/// [EnvelopeVerified.issuerConfirmed] false, as at_client 4.0.0 signed them,
/// until the release that re-signs what an enrollment publishes.
///
/// It is [selectEnvelopeKey] followed by one signature check against the key
/// it selects, so the two never disagree about which key that is.
@experimental
Future<EnvelopeVerification> verifySignedEnvelope(
  SignedEnvelope envelope, {
  required PublishedApsk signer,
  SigningAlgoType? minimumAlgorithm,
}) async {
  final selection = selectEnvelopeKey(envelope,
      signer: signer, minimumAlgorithm: minimumAlgorithm);
  switch (selection) {
    case EnvelopeRefused():
      return selection;
    case EnvelopeKeySelected(:final key, :final kid, _entry: final entry):
      final Uint8List signature;
      try {
        // NOTE: unpadded base64url only, so one signature has one spelling.
        if (!_unpaddedBase64Url.hasMatch(entry.signature)) {
          throw const FormatException('not unpadded base64url');
        }
        signature = base64Decode(base64Url.normalize(entry.signature));
      } on FormatException catch (e) {
        return EnvelopeRefused._(
            signer,
            EnvelopeRefusal.malformedEnvelope,
            'the signature of key ${quotedClaim(kid)} is not base64url: '
            '${e.message}',
            kid);
      }
      final Uint8List publicKey;
      try {
        publicKey = base64Decode(key.pub);
      } on FormatException catch (e) {
        return EnvelopeRefused._(
            signer,
            EnvelopeRefusal.malformedKeySet,
            'the _apsk lists key ${quotedClaim(kid)} with a key that is not '
            'base64: '
            '${e.message}',
            kid);
      }
      final bool verified;
      try {
        verified = await checkEnvelopeSignature(key.alg,
            input: utf8.encode('${entry.protected}.${envelope.payloadB64}'),
            signature: signature,
            publicKey: publicKey);
      } on Object catch (e) {
        return EnvelopeRefused._(
            signer,
            EnvelopeRefusal.malformedKeySet,
            'the _apsk lists key ${quotedClaim(kid)} in a form it cannot be '
            'used in: $e',
            kid);
      }
      if (!verified) {
        return EnvelopeRefused._(
            signer,
            EnvelopeRefusal.badSignature,
            'the ${key.alg.name} signature does not verify against key '
            '${quotedClaim(kid)}, which the _apsk lists and the envelope names',
            kid);
      }
      return EnvelopeVerified._(selection);
  }
}

/// Makes every check [verifySignedEnvelope] makes except the signature, and
/// reads neither the payload nor any key material; never throws.
///
/// Returns the key [verifySignedEnvelope] would check the signature against,
/// or the refusal it would return before checking any.
@experimental
EnvelopeKeySelection selectEnvelopeKey(
  SignedEnvelope envelope, {
  required PublishedApsk signer,
  SigningAlgoType? minimumAlgorithm,
}) {
  final reported = _reportedKid(envelope);
  EnvelopeRefused refuse(EnvelopeRefusal refusal, String reason) =>
      EnvelopeRefused._(signer, refusal, reason, reported);
  EnvelopeRefused refuseNaming(
          EnvelopeRefusal refusal, String reason, String? kid) =>
      EnvelopeRefused._(signer, refusal, reason, kid);

  if (exceedsUtf8Bytes(signer.value, maxPublishedApskLength)) {
    return refuse(EnvelopeRefusal.oversize, _oversize);
  }

  final typ = envelope.signature.typ;
  if (typ != EnvelopeType.app.typ) {
    return refuse(
        EnvelopeRefusal.wrongType,
        'the envelope is typed ${typ == null ? 'nothing' : quotedClaim(typ)}, and '
        'this verifies "${EnvelopeType.app.typ}"');
  }

  for (final entry in envelope.signatures) {
    if (entry.version != envelopeVersion) {
      return refuse(
          EnvelopeRefusal.unsupportedVersion,
          'an entry names envelope version "${entry.version}", and this '
          'build reads $envelopeVersion');
    }
  }

  final Atsign? claimed;
  try {
    claimed = issuerOf(envelope.signature);
  } on AtSigningVerificationException catch (e) {
    return refuse(EnvelopeRefusal.wrongAtSign, e.message);
  }
  if (claimed != null && claimed != signer.atSign) {
    return refuse(
        EnvelopeRefusal.wrongAtSign,
        'the envelope names its signer as ${quotedClaim(claimed)}, and the _apsk is '
        '"${signer.atSign}"\'s');
  }

  final enid = envelope.signerEnrollmentId;
  if (enid == null) {
    return refuse(
        EnvelopeRefusal.wrongEnrollment,
        'the envelope names no enrollment, and the _apsk is enrollment '
        '"${signer.enrollmentId}"\'s');
  }
  if (enid.toLowerCase() != signer.enrollmentId.toLowerCase()) {
    return refuse(
        EnvelopeRefusal.wrongEnrollment,
        'the envelope names enrollment ${quotedClaim(enid)}, and the _apsk is enrollment '
        '"${signer.enrollmentId}"\'s');
  }

  final reading = readApsk(signer.value);
  if (reading.fault case final fault?) {
    return refuse(EnvelopeRefusal.malformedKeySet, fault);
  }
  final usable = [
    for (final key in reading.keys)
      if (canSignEnvelopeWith(key.alg)) key
  ];
  if (usable.isEmpty) {
    return refuse(EnvelopeRefusal.malformedKeySet,
        'the _apsk lists no key this build can verify with');
  }

  final vouching = [
    for (final key in usable)
      if (key.vouchesForPastOperations) key
  ];
  final algorithm = SigningAlgoType.strongestOf({
    for (final key in vouching)
      if (envelope.signatures.any((s) => signsUnder(key.alg, s.alg))) key.alg
  });
  if (algorithm == null) {
    return _unlisted(envelope, usable, reported, refuseNaming);
  }
  final entry =
      envelope.signatures.firstWhere((s) => signsUnder(algorithm, s.alg));
  final kid = entry.kid;
  if (kid == null) {
    return refuseNaming(
        EnvelopeRefusal.malformedEnvelope,
        'the envelope\'s ${algorithm.name} signature names no key, and this '
        'build resolves the key by name',
        null);
  }
  final key =
      vouching.where((k) => k.alg == algorithm && k.kid == kid).firstOrNull;
  if (key == null) {
    return _unlistedKey(entry, algorithm, usable, refuseNaming);
  }

  if (minimumAlgorithm != null &&
      SigningAlgoType.strongestFirst.indexOf(algorithm) >
          SigningAlgoType.strongestFirst.indexOf(minimumAlgorithm)) {
    return refuseNaming(
        EnvelopeRefusal.algorithmTooWeak,
        'the strongest algorithm the envelope and the _apsk share is '
        '${algorithm.name}, weaker than the minimum ${minimumAlgorithm.name}',
        kid);
  }

  return EnvelopeKeySelected._(signer, key, claimed != null, entry);
}

/// The refusal for an envelope none of whose entries is signed under an
/// algorithm a vouching key of the `_apsk` uses.
EnvelopeRefused _unlisted(
  SignedEnvelope envelope,
  List<ApskSigningKey> usable,
  String? reported,
  _Refuse refuse,
) {
  for (final entry in envelope.signatures) {
    for (final key in usable) {
      if (key.kid == entry.kid && signsUnder(key.alg, entry.alg)) {
        return _notVouched(key, refuse);
      }
    }
  }
  return refuse(
      EnvelopeRefusal.keyNotInKeySet,
      'the envelope names ${quotedClaims(envelope.signatures.map((s) => s.kid))}, '
      'and the _apsk lists ${quotedClaims(usable.map((k) => k.kid))}',
      reported);
}

/// The refusal for [entry], selected under [algorithm], naming a key no
/// vouching entry of the `_apsk` lists.
EnvelopeRefused _unlistedKey(
  EnvelopeSignature entry,
  SigningAlgoType algorithm,
  List<ApskSigningKey> usable,
  _Refuse refuse,
) {
  final listed =
      usable.where((k) => k.alg == algorithm && k.kid == entry.kid).firstOrNull;
  if (listed != null) return _notVouched(listed, refuse);
  return refuse(
      EnvelopeRefusal.keyNotInKeySet,
      'the envelope\'s ${algorithm.name} signature names key '
      '${quotedClaim(entry.kid!)}, and the _apsk lists '
      '${quotedClaims(usable.map((k) => k.kid))}',
      entry.kid);
}

typedef _Refuse = EnvelopeRefused Function(
    EnvelopeRefusal refusal, String reason, String? kid);

EnvelopeRefused _notVouched(ApskSigningKey key, _Refuse refuse) => refuse(
    EnvelopeRefusal.keyNotVouchedFor,
    'the _apsk lists key ${quotedClaim(key.kid)} as ${quotedClaim(key.status)}, which does not '
    'vouch for what it signed',
    key.kid);

final RegExp _unpaddedBase64Url = RegExp(r'^[A-Za-z0-9_-]*$');

/// The kid of the entry signed under the strongest algorithm this build
/// reads, or null when no entry is.
String? _reportedKid(SignedEnvelope envelope) {
  final algorithm = SigningAlgoType.strongestOf({
    for (final algo in SigningAlgoType.values)
      if (canSignEnvelopeWith(algo) &&
          envelope.signatures.any((s) => signsUnder(algo, s.alg)))
        algo
  });
  if (algorithm == null) return null;
  return envelope.signatures
      .firstWhere((s) => signsUnder(algorithm, s.alg))
      .kid;
}
