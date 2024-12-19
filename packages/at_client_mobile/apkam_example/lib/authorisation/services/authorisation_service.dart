import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_utils/at_logger.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// {@template authorisation_service}
/// A service class for managing enrollment requests.
/// {@endtemplate}
class AuthorisationService with AtClientBindings {
  /// {@macro authorisation_service}
  AuthorisationService(this.atClient);

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('AuthorisationService');

  static const _kDefaultExpiry = Duration(minutes: 5);
  static const String _kSppRegex = r'[A-Za-z0-9]{6,16}';

  StreamController<EnrollmentRequest>? _enrollmentRequestsController;
  StreamSubscription? _newRequestsSubscription;

  /// Call this method before any other methods.
  ///
  /// Sets up the subscription to the server for new enrollment requests and
  /// fetches all existing requests.
  Future<void> init() async {
    logger.info('Initialising AuthorisationService');
    _enrollmentRequestsController ??= StreamController<EnrollmentRequest>.broadcast();
    _enrollmentRequestsController!.onListen = () async {
      final requests = await getAllEnrollmentRequests();
      for (final request in requests) {
        // TODO: I don't like this
        await Future<void>.delayed(const Duration(milliseconds: 100));
        _enrollmentRequestsController!.add(request);
      }
      _listenForNewRequests();
    };
  }

  void _listenForNewRequests() {
    assert(_enrollmentRequestsController != null, 'Call AuthorisationService.init() first');
    // Set up a stream to listen for new enrollment requests.
    final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    // Add the new requests to the stream controller.
    _newRequestsSubscription = stream.listen((AtNotification notification) async {
      try {
        logger.info('Enrollment request with id ${notification.key} received');
        final enrollmentRequest = EnrollmentRequest.fromServer(
          MapEntry(
            notification.key,
            jsonDecode(notification.value!),
          ),
        );
        if (!_enrollmentRequestsController!.isClosed) {
          _enrollmentRequestsController!.add(enrollmentRequest);
        }
      } catch (e, st) {
        logger.severe('Failed to process new enrollment request.', e, st);
        _enrollmentRequestsController!.addError(UnexpectedResponseException(e.toString()));
      }
    });
  }

  /// Call this method when the service is no longer needed.
  ///
  /// Closes and cancels all streams and subscriptions.
  Future<void> dispose() async {
    await _newRequestsSubscription?.cancel();
    await _enrollmentRequestsController?.close();
  }

  /// Stream of all enrollment requests.
  /// Use this for getting real-time updates on new requests.
  Stream<EnrollmentRequest> get enrollmentRequests {
    if (_enrollmentRequestsController == null) {
      throw StateError('init() must be called before accessing enrollmentRequests');
    }
    return _enrollmentRequestsController!.stream;
  }

  /// Get all enrollment requests. This includes all past and pending requests.
  /// Empty list means no requests.
  Future<List<EnrollmentRequest>> getAllEnrollmentRequests() async {
    // Get the lookup service from the secondary server.
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;

    // Command to send to the server to get all pending enrollments.
    const command = 'enroll:list';

    // Send the command to the server.
    final rawResponse = await atLookup.executeCommand(
      '$command\n',
      auth: true,
    );

    // Parse the raw response.
    if (rawResponse == null || !rawResponse.startsWith('data:')) {
      logger.severe(
        'Invalid response from the server. Expected it to start with `data:`. Response: $rawResponse',
        null,
        StackTrace.current,
      );
      throw UnexpectedResponseException(rawResponse ?? 'No response from server');
    }
    final rawData = rawResponse.substring(rawResponse.indexOf('data:') + 5);
    final data = jsonDecode(rawData) as Map<String, dynamic>;
    // TODO: Filter out `firstApp` enrolment
    final enrollmentRequests = data.entries.map(EnrollmentRequest.fromServer).toList();
    logger.info('Found ${enrollmentRequests.length} enrollmentRequests');
    logger.finer('Enrollment Requests: $enrollmentRequests');
    return enrollmentRequests;
  }

  /// Check if the current atSign has manager permissions.
  Future<bool> isManagerKey() async {
    final enrollments = await getAllEnrollmentRequests();
    // Check if one of the enrollments has read and write permissions for the __manage namespace.
    final hasManagePermission = enrollments.any(
      (e) =>
          e.namespacePermissions.any((p) => p.namespace == '__manage' && p.write && p.read) &&
          e.status == EnrollmentStatus.approved,
    );
    logger.info('Has manage permissions: $hasManagePermission');
    return hasManagePermission;
  }

  /// Check if the given spp is valid.
  /// Must be alphanumeric and 6 to 16 characters long.
  bool _isSppValid(String otp) {
    final regex = RegExp('^$_kSppRegex\$');
    return regex.hasMatch(otp);
  }

  /// Set a semi-permanent passcode/OTP.
  ///
  /// This is used to approve enrollments.
  /// It can be useful to set an spp if enrolling many devices at once.
  ///
  /// The [spp] must be alphanumeric and 6 to 16 characters long.
  ///
  /// [sppExpiry] Defaults to 5 minutes.
  Future<void> setSpp({
    required String spp,
    Duration sppExpiry = _kDefaultExpiry,
  }) async {
    logger.finer(
      'Setting spp to $spp expiring in ${sppExpiry.inSeconds}s (${DateTime.now().add(sppExpiry).toIso8601String()})',
    );
    if (!_isSppValid(spp)) {
      throw InvalidSppException();
    }

    final command = 'otp:put:$spp:ttl:${sppExpiry.inMilliseconds}\n';

    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final response = await atLookup.executeCommand(command, auth: true);
    // TODO: Add error handling
    debugPrint(response);
    logger.info('SPP set successfully');
  }

  /// Get the OTP from the server.
  ///
  /// If an spp is set, the server will return the spp,
  /// otherwise it will return a randomly generated OTP.
  ///
  /// [optExpiry] Defaults to 5 minutes.
  ///
  /// Throws [OtpGenerationException] if the OTP could not be generated.
  Future<String> generateOtp({Duration optExpiry = _kDefaultExpiry}) async {
    final command = 'otp:get:ttl:${optExpiry.inMilliseconds}\n';

    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final response = await atLookup.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5);
      assert(otp.length >= 6, 'OTP should be 6 or more characters');
      logger.finer('OTP generated: $otp');
      return otp;
    } else {
      logger.severe('Invalid response from the server. Expected it to start with `data:`. Response: $response');
      throw OtpGenerationException(response ?? 'No response from server');
    }
  }

  /// Approve the given [enrollmentRequest].
  ///
  /// Throws [FailedToApproveException] if the request was not approved.
  Future<void> approve(EnrollmentRequest enrollmentRequest) async {
    // Get the lookup service from the secondary server.
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await atAuthBase.atEnrollment(atSign).approve(
          EnrollmentRequestDecision.approved(
            ApprovedRequestDecisionBuilder(
              enrollmentId: enrollmentRequest.enrollmentId,
              encryptedAPKAMSymmetricKey: enrollmentRequest.encryptedAPKAMSymmetricKey!,
            ),
          ),
          atLookup,
        );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.approved) {
      logger.severe(
        'Failed to approve enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToApproveException();
    }
    logger.info('Enrollment request with id ${enrollmentRequest.enrollmentId} approved');
    return;
  }

  /// Deny the given [enrollmentRequest].
  ///
  /// Throws [FailedToDenyException] if the request was not denied.
  Future<void> deny(EnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await atAuthBase.atEnrollment(atSign).deny(
          EnrollmentRequestDecision.denied(
            enrollmentRequest.enrollmentId,
          ),
          atLookup,
        );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.denied) {
      logger.severe(
        'Failed to deny enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToDenyException();
    }
    logger.info('Enrollment request with id ${enrollmentRequest.enrollmentId} denied');
    return;
  }

  /// Revoke the given [enrollmentRequest].
  ///
  /// This is for denying a previously approved request.
  /// Throws [FailedToRevokeException] if the request was not revoked.
  Future<void> revoke(EnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await atAuthBase.atEnrollment(atSign).revoke(
          EnrollmentRequestDecision.revoked(
            enrollmentRequest.enrollmentId,
          ),
          atLookup,
        );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.revoked) {
      logger.severe(
        'Failed to revoke enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToRevokeException();
    }
    logger.info('Enrollment request with id ${enrollmentRequest.enrollmentId} revoked');
    return;
  }
}

/// {@template enrollment_request}
/// A model representing an enrollment request.
/// {@endtemplate}
@immutable
class EnrollmentRequest {
  /// {@macro enrollment_request}
  const EnrollmentRequest({
    required this.enrollmentId,
    required this.appName,
    required this.deviceName,
    required this.status,
    required this.namespacePermissions,
    this.encryptedAPKAMSymmetricKey,
  }) : assert(
          status != EnrollmentStatus.pending || encryptedAPKAMSymmetricKey != null,
          'Pending requests should have an encryptedAPKAMSymmetricKey',
        );

  /// The unique identifier for this enrollment request.
  final String enrollmentId;

  /// The name of the app that is requesting access.
  final String appName;

  /// The name of the device that is requesting access.
  final String deviceName;

  /// The current status of the request.
  final EnrollmentStatus status;

  /// The encrypted APKAM symmetric key.
  /// Will only be present if the request is pending TODO: Check if this is correct.
  final String? encryptedAPKAMSymmetricKey;

  /// List of permissions requested by the app and device.
  /// Empty list means no permissions.
  final List<NamespacePermission> namespacePermissions;

  /// Creates an [EnrollmentRequest] object from a server response.
  factory EnrollmentRequest.fromServer(MapEntry<String, dynamic> entry) {
    // Example id: a7d6a9.....40a15.new.enrollments.__manage@alice
    // Only interested in the first part.
    final enrollmentId = entry.key.split('.').first;
    return EnrollmentRequest(
      enrollmentId: enrollmentId,
      appName: entry.value['appName'] as String,
      deviceName: entry.value['deviceName'] as String,
      // Status can be null when received from a notification
      status: entry.value['status'] != null
          ? getEnrollStatusFromString(entry.value['status'] as String)
          : EnrollmentStatus.pending,
      encryptedAPKAMSymmetricKey: entry.value['encryptedAPKAMSymmetricKey'] as String?,
      // Looks like: `namespace: {ns1: rw, ns2: r}`
      namespacePermissions: (entry.value['namespace'] as Map<String, dynamic>)
          .cast<String, String>()
          .entries
          .map((e) => NamespacePermission(
                namespace: e.key,
                read: e.value.contains('r'),
                write: e.value.contains('w'),
              ))
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EnrollmentRequest &&
        other.enrollmentId == enrollmentId &&
        other.appName == appName &&
        other.deviceName == deviceName &&
        other.status == status &&
        other.encryptedAPKAMSymmetricKey == encryptedAPKAMSymmetricKey &&
        const DeepCollectionEquality().equals(other.namespacePermissions, namespacePermissions);
  }

  @override
  int get hashCode =>
      enrollmentId.hashCode ^
      appName.hashCode ^
      deviceName.hashCode ^
      status.hashCode ^
      namespacePermissions.hashCode ^
      encryptedAPKAMSymmetricKey.hashCode;

  @override
  String toString() {
    return 'EnrollmentRequest(enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName, status: $status, namespaces: $namespacePermissions, encryptedAPKAMSymmetricKey: ${encryptedAPKAMSymmetricKey?.substring(0, 10)})';
  }
}

/// {@template namespace_permission}
/// Model class representing a namespace permission.
/// The string representation of the permission is `namespace: {ns1: rw, ns2: r}`
/// where read is `r` and write is `w` and `ns1`/`ns2` are the namespaces.
/// {@endtemplate}
@immutable
class NamespacePermission {
  /// {@macro namespace_permission}
  const NamespacePermission({
    required this.namespace,
    this.read = false,
    this.write = false,
  });

  /// The namespace that the permission applies to.
  final String namespace;

  /// Whether the app/device has read access to the namespace.
  final bool read;

  /// Whether the app/device has write access to the namespace.
  final bool write;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is NamespacePermission && other.namespace == namespace && other.read == read && other.write == write;
  }

  @override
  int get hashCode => namespace.hashCode ^ read.hashCode ^ write.hashCode;

  @override
  String toString() {
    return 'NamespacePermission(namespace: $namespace, read: $read, write: $write)';
  }
}

class AuthorisationException implements Exception {
  AuthorisationException(this.message);

  final String message;

  @override
  String toString() {
    return 'AuthorisationException: $message';
  }
}

final class InvalidSppException extends AuthorisationException {
  InvalidSppException() : super('SPP must be alphanumeric and 6 to 16 characters long');
}

final class OtpGenerationException extends AuthorisationException {
  OtpGenerationException(String serverMessage) : super('Failed to generate OTP: $serverMessage');
}

final class UnexpectedResponseException extends AuthorisationException {
  UnexpectedResponseException(String response) : super('Unexpected server response: $response');
}

final class FailedToApproveException extends AuthorisationException {
  FailedToApproveException() : super('Failed to approve enrollment request');
}

final class FailedToDenyException extends AuthorisationException {
  FailedToDenyException() : super('Failed to deny enrollment request');
}

final class FailedToRevokeException extends AuthorisationException {
  FailedToRevokeException() : super('Failed to revoke enrollment request');
}
