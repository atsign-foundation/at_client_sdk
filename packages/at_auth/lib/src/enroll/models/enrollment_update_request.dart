import 'package:at_auth/src/enroll/apsk_advertisement.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_commons/at_commons.dart' show AtEnrollmentException;

/// What an approved enrollment is asking to change about its **own** record,
/// through `enroll:update`.
///
/// The operation reaches four things and nothing else: the APKAM
/// authentication public key (and the algorithm that describes it), the `_apsk`
/// signing-key advertisement, and the opaque metadata. It cannot reach the
/// namespaces or the approval state — an enrollment that could amend those
/// could widen its own grant, which is privilege escalation with a valid
/// signature on it — and the atServer refuses a request that names them.
///
/// It is self-only: the connection must be authenticated as the enrollment
/// being updated. An owner connection is refused rather than waved through,
/// because an owner cannot sign anything with this enrollment's APKAM private
/// key and so could only deny it service.
///
/// ```dart
/// // Advertise a second algorithm's signing key beside the first.
/// final request = EnrollmentUpdateRequest(
///   enrollmentId: enrollmentId,
///   signingKeys: [
///     ApskSigningKey.forPublicKey(
///         alg: SigningAlgoType.mldsa65, pub: mlDsaPublicKey),
///     ApskSigningKey.forPublicKey(
///         alg: SigningAlgoType.rsa2048, pub: rsaPublicKey),
///   ],
/// );
/// await atEnrollment.update(request, atLookUp);
/// ```
class EnrollmentUpdateRequest {
  /// The enrollment being amended, which must be the one the connection is
  /// authenticated as.
  final String enrollmentId;

  /// The APKAM authentication public key to move this enrollment onto, or null
  /// to leave it as it is.
  ///
  /// ⚠️ **Nothing here writes the new keypair to a keyfile.** The atServer
  /// judges every later authentication against the record, so an enrollment
  /// whose rotation lands and whose new private key is not persisted cannot
  /// authenticate again — by anyone, ever. A caller that rotates persists
  /// first, or persists on success and treats a failure to do so as the
  /// emergency it is.
  final String? apkamPublicKey;

  /// The private half of [apkamPublicKey]. **Never sent** — it signs the proof
  /// of possession the atServer requires before it will install the public
  /// half.
  ///
  /// The connection proves possession of the enrollment's *current* key and
  /// nothing else proves possession of the new one, so without that proof a
  /// compromised-but-authenticated client could install a key whose private
  /// half is held by someone else, locking out the legitimate holder while the
  /// enrollment record still looks entirely valid.
  final String? apkamPrivateKey;

  /// The algorithm [apkamPublicKey] is spelled in — required with it and
  /// meaningless without it, in both directions.
  ///
  /// The wire permits omitting it, and the atServer then keeps whatever the
  /// record already names. That form is not composed here: the omitted value
  /// still goes into the bytes the possession proof signs, so a client sending
  /// it has to already know what the record holds, and a client that guesses
  /// wrong produces a signature the server computes differently and rejects
  /// with nothing to point at. Naming it costs a caller nothing — re-stating
  /// the algorithm a record already holds changes nothing about that record.
  final SigningAlgoType? signingAlgo;

  /// The signing keys to advertise at
  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>`, replacing what is published
  /// there, or null to leave the advertisement alone.
  ///
  /// A key that has stopped signing is listed with
  /// `KeyEntryStatus.retired` rather than dropped: envelopes are stored durably
  /// and verified later, so the keys an enrollment has retired are exactly the
  /// ones that signed its older ones, and withdrawing one retroactively
  /// unverifies everything it signed.
  final List<ApskSigningKey>? signingKeys;

  /// The **bare** RSA `_apsk` string to publish verbatim, for an enrollment
  /// that must keep the shape every deployed consumer parses.
  ///
  /// Mutually exclusive with [signingKeys] — one enrollment publishes one
  /// `_apsk` value, and the atServer refuses a request carrying both because it
  /// has no basis for choosing between two descriptions of one record.
  final String? apskLegacy;

  /// Metadata to merge into the record's, or null to leave it alone.
  ///
  /// A per-key merge, not a whole-map replace: keys this request does not name
  /// survive untouched, so a client that does not know about a field a later
  /// build added cannot clobber it.
  final Map<String, dynamic>? metadata;

  EnrollmentUpdateRequest({
    required this.enrollmentId,
    this.apkamPublicKey,
    this.apkamPrivateKey,
    this.signingAlgo,
    this.signingKeys,
    this.apskLegacy,
    this.metadata,
  }) {
    if ((apkamPublicKey == null) != (apkamPrivateKey == null)) {
      throw AtEnrollmentException(
          'a rotation supplies both halves of the APKAM keypair: the public '
          'half is what the atServer installs, and the private half is the '
          'only thing that can prove the sender holds it');
    }
    if ((apkamPublicKey == null) != (signingAlgo == null)) {
      throw AtEnrollmentException(
          'apkamPublicKey and signingAlgo are supplied together: the algorithm '
          'describes the key, and each is unusable without the other — the '
          'atServer refuses an algorithm with no key, and the possession '
          'proof over a key needs the algorithm to sign under');
    }
    if (signingKeys != null && apskLegacy != null) {
      throw AtEnrollmentException(
          'signingKeys and apskLegacy are mutually exclusive: one enrollment '
          'publishes one _apsk value');
    }
    if (signingKeys != null && signingKeys!.isEmpty) {
      throw AtEnrollmentException(
          'an _apsk advertising no key at all is one every reader refuses, '
          'which leaves this enrollment unable to have anything it signs '
          'verified; omit signingKeys to leave the advertisement alone');
    }
    if (apkamPublicKey == null &&
        signingKeys == null &&
        apskLegacy == null &&
        metadata == null) {
      throw AtEnrollmentException(
          'an enroll:update must name something to change: an APKAM keypair, '
          'signing keys, a legacy _apsk or metadata');
    }
  }
}
