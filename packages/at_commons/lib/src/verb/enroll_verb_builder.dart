import 'dart:convert';

import 'package:at_commons/src/enroll/enrollment.dart';
import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/enroll_params.dart';

import 'operation_enum.dart';

/// Enroll verb builder generates enroll verb command for APKAM(Application PKAM) authentication process.
class EnrollVerbBuilder extends AbstractVerbBuilder {
  String? enrollmentId;

  /// Operation type of the enroll verb - request/approve/deny. Default value will be request
  EnrollOperationEnum operation = EnrollOperationEnum.request;

  /// Name of the mobile application or client sending the enroll verb.
  String? appName;

  /// Name of the device sending the enroll verb.
  String? deviceName;

  /// Public key of an asymmetric key pair generated on the app or client.
  String? apkamPublicKey;

  /// otp for the enroll request. otp must be fetched from an already enrolled app.
  String? otp;

  Map<String, String>? namespaces;

  @Deprecated('Use encryptedDefaultEncryptionPrivateKey')
  String? encryptedDefaultEncryptedPrivateKey;

  String? encryptedDefaultEncryptionPrivateKey;

  /// Initialisation vector used during symmetric encryption of the default encryption key.
  String? encPrivateKeyIV;

  String? encryptedDefaultSelfEncryptionKey;

  /// Initialisation vector used during symmetric encryption of the default self encryption key.
  String? selfEncKeyIV;

  String? encryptedAPKAMSymmetricKey;

  /// The signing algorithm of [apkamPublicKey] — `rsa2048` or `mldsa65`.
  /// Recorded on the enrollment so PKAM verification is record-authoritative.
  String? signingAlgo;

  /// Opaque, additive metadata stored verbatim on the enrollment record and
  /// returned from discovery (`enroll:listns`). Carries the enrollment's key
  /// package (`metadata.keyPackage`) for the secret-sharing substrate.
  Map<String, dynamic>? metadata;

  /// The value to publish as this enrollment's `_apsk` signing key. See
  /// [EnrollParams.apsk] for the shape and why the atServer composes nothing.
  ///
  /// An enrollment that sends neither this nor [apskLegacy] gets no `_apsk`
  /// published, and an approver then has no key to verify its advertised key
  /// package against.
  Map<String, dynamic>? apsk;

  /// The bare RSA `_apsk` string, published verbatim. See
  /// [EnrollParams.apskLegacy]. Mutually exclusive with [apsk].
  String? apskLegacy;

  /// Proof that the sender holds the private half of the [apkamPublicKey] it
  /// is asking the atServer to install. See
  /// [EnrollParams.apkamPublicKeySignature] for what is signed and why.
  ///
  /// Required on an `enroll:update` that changes [apkamPublicKey], and refused
  /// without it.
  String? apkamPublicKeySignature;

  /// Used to force revoke the enrollment request.
  bool force = false;

  /// Filters enrollment requests based on provided [EnrollmentStatus] criteria.
  ///
  /// Accepts a list of enrollment statuses. Defaults to all EnrollmentStatuses
  List<EnrollmentStatus>? enrollmentStatusFilter;

  Duration? apkamKeysExpiryDuration;

  @override
  String buildCommand() {
    var sb = StringBuffer();
    sb.write('enroll:');
    sb.write(getEnrollOperation(operation));
    if (force) {
      sb.write(':force');
    }

    EnrollParams enrollParams = EnrollParams()
      ..enrollmentId = enrollmentId
      ..appName = appName
      ..deviceName = deviceName
      ..apkamPublicKey = apkamPublicKey
      ..otp = otp
      ..namespaces = namespaces
      ..encryptedDefaultEncryptionPrivateKey =
          encryptedDefaultEncryptionPrivateKey
      ..encPrivateKeyIV = encPrivateKeyIV
      ..encryptedDefaultSelfEncryptionKey = encryptedDefaultSelfEncryptionKey
      ..selfEncKeyIV = selfEncKeyIV
      ..encryptedAPKAMSymmetricKey = encryptedAPKAMSymmetricKey
      ..signingAlgo = signingAlgo
      ..apsk = apsk
      ..apskLegacy = apskLegacy
      ..apkamPublicKeySignature = apkamPublicKeySignature
      ..metadata = metadata
      ..enrollmentStatusFilter = enrollmentStatusFilter
      ..apkamKeysExpiryDuration = apkamKeysExpiryDuration;

    Map<String, dynamic> enrollParamsJson = enrollParams.toJson();
    enrollParamsJson.removeWhere(_removeElements);
    if (enrollParamsJson.isNotEmpty) {
      sb.write(':${jsonEncode(enrollParamsJson)}');
    }
    sb.write('\n');
    return sb.toString();
  }

  /// Compares current EnrollOperation with VerbBuilder params and removes any
  /// that are NOT applicable
  ///
  ///
  /// Returning "false" will leave the key and its value in the map, which gets added to the
  /// enroll verb command. Returning true will remove the key and its value from the map to
  /// to refrain adding the key and its value to the enroll verb command.
  bool _removeElements(String key, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return true;
    }
    // Drop an empty metadata map so it never reaches the wire.
    if (value is Map && value.isEmpty) {
      return true;
    }
    // EnrollmentStatusFilter is only applicable to EnrollOperation.list
    // Remove it from enrollParamsJson for any operation other than list
    if (key == 'enrollmentStatusFilter' &&
        operation != EnrollOperationEnum.list) {
      return true;
    }
    return false;
  }

  @override
  bool checkParams() {
    return appName != null &&
        deviceName != null &&
        namespaces != null &&
        namespaces!.isNotEmpty &&
        otp != null &&
        apkamPublicKey != null;
  }
}
