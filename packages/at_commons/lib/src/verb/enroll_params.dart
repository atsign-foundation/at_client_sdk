import 'package:at_commons/at_commons.dart';
import 'package:json_annotation/json_annotation.dart';

part 'enroll_params.g.dart';

@JsonSerializable()
class EnrollParams {
  String? enrollmentId;
  String? appName;
  String? deviceName;
  Map<String, String>? namespaces;
  String? otp;
  String? encryptedDefaultEncryptionPrivateKey;
  String? encPrivateKeyIV;
  String? encryptedDefaultSelfEncryptionKey;
  String? selfEncKeyIV;
  String? encryptedAPKAMSymmetricKey;
  String? apkamPublicKey;

  /// The signing algorithm of [apkamPublicKey] — `rsa2048` (legacy default) or
  /// `mldsa65` (PQ). Recorded on the enrollment so PKAM verification is
  /// record-authoritative.
  String? signingAlgo;

  /// The value to publish as this enrollment's APKAM public signing key at
  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>`, composed by the client.
  ///
  /// Opaque to the atServer, which stores it verbatim on the enrollment record
  /// and writes its JSON encoding unaltered when the enrollment is approved,
  /// and again whenever an `enroll:update` carries a new one. The contents are
  /// the client's alone, so a shape added later needs no server release.
  ///
  /// The form the client composes is a versioned array of signing keys,
  /// spelled as `KeyPackage`'s keys are so that one vocabulary covers every
  /// "list of keys with algorithms" in the protocol. `apskAdvertisement` in
  /// at_auth composes it and `apskSigningKeys` reads it back:
  ///
  /// ```json
  /// {"v": 1, "keys": [
  ///   {"kid": "…", "use": "sign", "alg": "mldsa65", "pub": "…"}
  /// ]}
  /// ```
  ///
  /// An array from the outset even though an enrollment holds one signing key
  /// today: a second algorithm's key is added beside the first rather than
  /// replacing it, because envelopes are stored durably and verified later, so
  /// a key that stops being used must still verify what it already signed. A
  /// reader skips entries whose `use` or `alg` it does not know, which is what
  /// lets an enrollment advertise a new algorithm without breaking readers
  /// that predate it.
  ///
  /// A per-entry `status` (`active` | `retired`, absent reading as `active`)
  /// arrives with the retired-key path; nothing composes or reads it yet.
  ///
  /// A map rather than a string, because this is the structured form. The bare
  /// RSA spelling `_apsk` has always carried travels on [apskLegacy] instead —
  /// two fields rather than one field of two types, so neither the wire type
  /// nor the atServer's handling has to be widened later.
  ///
  /// Absent means **no `_apsk` is published** from this field. The atServer
  /// never composes one from [apkamPublicKey] and [signingAlgo]: PKAM
  /// verification reads the enrollment record, so the server has no use for
  /// this key and no business knowing how a signing key is spelled.
  ///
  /// Capped by the atServer at 20KB **encoded**; a longer value is refused
  /// rather than truncated.
  Map<String, dynamic>? apsk;

  /// The **bare** `_apsk` value — an RSA public key string, exactly as the
  /// record has always carried it — to publish verbatim at
  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>`.
  ///
  /// This exists because every deployed `_apsk` consumer base64-decodes the
  /// value as an RSA key, so a JSON one fails their parse. That is fail-closed
  /// but service-breaking for anything already running, which is why a
  /// plain-legacy enrollment must be able to publish the shape they expect
  /// through the same verb every other enrollment uses.
  ///
  /// Written verbatim, **not** JSON-encoded: a quoted string is not what a
  /// bare-RSA parser reads. Sending this together with [apsk] is a client
  /// error and the atServer refuses it — the two would disagree about one
  /// record, and the server has no basis for choosing between them.
  String? apskLegacy;

  /// Proof that the sender holds the private half of the [apkamPublicKey] it
  /// is asking the atServer to install — base64 of a signature by that **new**
  /// private key over `<enrollmentId>|<apkamPublicKey>|<signingAlgo>`.
  ///
  /// Required on an `enroll:update` that changes [apkamPublicKey], and refused
  /// without it. The connection proves possession of the enrollment's
  /// *current* key; nothing else proves possession of the new one, so without
  /// this a compromised-but-authenticated client can install a public key
  /// whose private half is held by someone else, locking out the legitimate
  /// holder while the enrollment record still looks valid.
  ///
  /// No nonce, deliberately. The operation is self-only over an authenticated
  /// connection, and the old key stops authenticating the moment the rotation
  /// lands, so a replayed request can only be sent by the current holder —
  /// which makes a rollback self-harm rather than an attack.
  String? apkamPublicKeySignature;

  /// Opaque, additive metadata the server stores verbatim on the enrollment
  /// record and returns from discovery (`enroll:listns`). Carries the
  /// enrollment's key package (`metadata.keyPackage`) for the secret-sharing
  /// substrate; the server has no opinion on its contents.
  Map<String, dynamic>? metadata;

  List<EnrollmentStatus>? enrollmentStatusFilter;
  Duration? apkamKeysExpiryDuration;

  EnrollParams();

  factory EnrollParams.fromJson(Map<String, dynamic> json) =>
      _$EnrollParamsFromJson(json);

  Map<String, dynamic> toJson() => _$EnrollParamsToJson(this);
}
