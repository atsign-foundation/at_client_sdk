import 'dart:convert';
import 'dart:typed_data';

import 'passkey_record.dart' show UnsupportedPasskeyRecordException;

/// An activated atSign whose sealed @keys are not yet filed on the atServer,
/// kept on the device that activated it.
///
/// Everything outside [sealed] is a header: it names which passkey opens the
/// record and lets a caller recognise it, and is not authenticated, so a
/// caller trusts only what [sealed] holds once it has opened it.
class PendingOnboardingRecord {
  /// A record for the passkey [credentialId], whose sealed body is [sealed].
  PendingOnboardingRecord(
      {required this.credentialId,
      required this.enrollmentId,
      this.encryptionPublicKey,
      required this.sealed});

  /// Reads a record written by [toJson].
  ///
  /// Throws [UnsupportedPasskeyRecordException] when [json] is not one.
  factory PendingOnboardingRecord.fromJson(Map<String, dynamic> json) {
    final credentialId = json['credentialId'];
    final enrollmentId = json['enrollmentId'];
    final encryptionPublicKey = json['encryptionPublicKey'];
    final sealed = json['sealed'];
    if (credentialId is! String ||
        enrollmentId is! String ||
        sealed is! String ||
        (encryptionPublicKey != null && encryptionPublicKey is! String)) {
      throw UnsupportedPasskeyRecordException(
          'malformed pending onboarding record');
    }
    try {
      return PendingOnboardingRecord(
          credentialId: base64Decode(credentialId),
          enrollmentId: enrollmentId,
          encryptionPublicKey: encryptionPublicKey as String?,
          sealed: sealed);
    } on FormatException {
      throw UnsupportedPasskeyRecordException(
          'pending onboarding record credential id is not base64');
    }
  }

  /// The passkey that sealed [sealed], which a retry asserts to open it.
  final Uint8List credentialId;

  /// The enrollment the activation created, as the device saw it.
  final String enrollmentId;

  /// The atSign's encryption public key, when the activation minted one.
  final String? encryptionPublicKey;

  /// The record `{enrollmentId, atKeys}` sealed by the passkey's vault.
  final String sealed;

  /// This record as a JSON object.
  Map<String, dynamic> toJson() => {
        'credentialId': base64Encode(credentialId),
        'enrollmentId': enrollmentId,
        if (encryptionPublicKey != null)
          'encryptionPublicKey': encryptionPublicKey,
        'sealed': sealed,
      };

  @override
  String toString() => 'PendingOnboardingRecord($enrollmentId)';
}

/// Where a device keeps the [PendingOnboardingRecord] of an atSign it has
/// activated but not finished onboarding.
///
/// Durable across a reload of the origin, scoped to the origin, and holding at
/// most one record per canonical atSign.
abstract class PendingOnboardingStore {
  /// The record kept for [atSign], or null.
  Future<PendingOnboardingRecord?> get(String atSign);

  /// Keeps [record] for [atSign], replacing any earlier one.
  Future<void> put(String atSign, PendingOnboardingRecord record);

  /// Removes [atSign]'s record. Does nothing when there is none.
  Future<void> delete(String atSign);
}
