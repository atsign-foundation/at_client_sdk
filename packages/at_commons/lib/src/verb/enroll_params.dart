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
  /// The form the client composes today is a versioned array of signing keys,
  /// spelled as `KeyPackage`'s keys are so that one vocabulary covers every
  /// "list of keys with algorithms" in the protocol:
  ///
  /// ```json
  /// {"v": 1, "keys": [
  ///   {"use": "sign", "alg": "mldsa65", "pub": "…", "status": "active"},
  ///   {"use": "sign", "alg": "rsa2048", "pub": "…", "status": "verifyOnly"}
  /// ]}
  /// ```
  ///
  /// `status` absent reads as `active`. An entry is retained after it stops
  /// signing — envelopes are stored durably and re-verified later, so removing
  /// a key would retroactively unverify everything ever signed with it.
  ///
  /// A map rather than a string, matching [metadata]: the bare RSA spelling
  /// `_apsk` has always carried is the *legacy* form, and a client old enough
  /// to publish it does not send this field at all.
  ///
  /// Absent means **no `_apsk` is published**. The atServer never composes one
  /// from [apkamPublicKey] and [signingAlgo]: PKAM verification reads the
  /// enrollment record, so the server has no use for this key and no business
  /// knowing how a signing key is spelled. An enrollment that sends nothing
  /// here publishes its own signing key from its own connection, or goes
  /// without.
  ///
  /// Capped by the atServer at 20KB **encoded**; a longer value is refused
  /// rather than truncated.
  Map<String, dynamic>? apsk;

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
