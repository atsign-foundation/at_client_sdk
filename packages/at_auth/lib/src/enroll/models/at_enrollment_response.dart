import 'dart:async' show FutureOr;

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUp;

/// Base class for enrollment-related data objects.
///
/// Provides a unified interface for accessing [enrollmentId] and
/// [enrollmentStatus] on enrollment operation results
/// ([AtEnrollmentResponse]).
abstract class AtEnrollmentRecord {
  String get enrollmentId;
  EnrollmentStatus get enrollmentStatus;
}

/// Backward compatibility for [AtEnrollmentRecord]
typedef EnrollmentBase = AtEnrollmentRecord;

/// Represents the response of an enrollment operation received
/// from the secondary server.
class AtEnrollmentResponse extends AtEnrollmentRecord {
  /// The unique identifier associated with the enrollment.
  @override
  String enrollmentId;

  /// The status of the enrollment operation.
  EnrollmentStatus enrollStatus;

  @override
  EnrollmentStatus get enrollmentStatus => enrollStatus;

  /// Optional atSign associated with the enrollment.
  @Deprecated('Use `session.atSign` instead.')
  String? atSign;

  /// Optional root domain associated with the enrollment.
  @Deprecated('Use `session.rootDomain` instead.')
  AtRootDomain? rootDomain;

  /// The authentication keys associated with the enrollment.
  @Deprecated(
      'Use `session` instead; the keys are sourced via `session.atKeysIo`.')
  AtKeys? atAuthKeys;

  /// The hand-off session for the newly enrolled app, populated on the
  /// requesting-app success path once the enrollment is approved.
  ///
  /// Pass it straight into `AtClientManager.fromAuthSession(...)`; the client
  /// derives its own keys via [AtAuthSession.atKeysIo] rather than adopting the
  /// deprecated [atAuthKeys] material directly.
  AtAuthSession? session;

  /// Carried over from `AtEnrollmentRequest.apkamSymmetricKeyResolver` so
  /// `waitForApproval` can collect the symmetric key the approver encapsulated
  /// to this enrollment's key package. Non-null exactly when the request
  /// advertised a key package, and therefore sent no RSA-wrapped key for the
  /// approver to hand back.
  FutureOr<String> Function(AtKeys keys, AtLookUp atLookUp)?
      apkamSymmetricKeyResolver;

  /// Creates an instance of [AtEnrollmentResponse].
  ///
  /// The [enrollmentId] is the unique identifier for the enrollment.
  /// The [enrollStatus] represents the status of the enrollment operation.
  /// The [session] is the hand-off session for the newly enrolled app.
  AtEnrollmentResponse(this.enrollmentId, this.enrollStatus,
      {this.atSign,
      this.rootDomain,
      this.atAuthKeys,
      this.session,
      this.apkamSymmetricKeyResolver});

  @override
  String toString() {
    return 'AtEnrollmentResponse{enrollmentId: $enrollmentId, enrollStatus: $enrollStatus}';
  }

  Map<String, dynamic> toJson() {
    return {
      'enrollmentId': enrollmentId,
      'enrollStatus': enrollStatus.name,
      if (atSign != null) 'atSign': atSign,
    };
  }

  factory AtEnrollmentResponse.fromJson(Map<String, dynamic> json) {
    String enrollmentId = json['enrollmentId'];
    EnrollmentStatus enrollmentStatus = EnrollmentStatus.values
        .firstWhere((es) => es.name == json['enrollStatus']);
    String? atSign = json['atSign'];

    return AtEnrollmentResponse(enrollmentId, enrollmentStatus, atSign: atSign);
  }
}
