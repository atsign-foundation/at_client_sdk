import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:flutter/foundation.dart';

class AuthorisationService {
  AuthorisationService(this.atClient);

  final AtClient atClient;

  static const _kDefaultExpiry = Duration(minutes: 5);
  static const String _kSppRegex = r'[A-Za-z0-9]{6,16}';

  StreamController<EnrollmentRequest>? _enrollmentRequestsController;
  StreamSubscription? _newRequestsSubscription;

  /// Call this method before any other methods.
  ///
  /// Sets up the subscription to the server for new enrollment requests and
  /// fetches all existing requests.
  Future<void> init() async {
    _enrollmentRequestsController ??= StreamController<EnrollmentRequest>.broadcast();
    _enrollmentRequestsController!.onListen = () async {
      final requests = await getAllEnrollmentRequests();
      for (final request in requests) {
        _enrollmentRequestsController!.add(request);
      }
      _listenForNewRequests();
    };
  }

  void _listenForNewRequests() async {
    assert(_enrollmentRequestsController != null, 'Call AuthorisationService.init() first');
    // Set up a stream to listen for new enrollment requests.
    final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    // Add the new requests to the stream controller.
    _newRequestsSubscription = stream.listen((AtNotification notification) {
      try {
        final enrollmentRequest = EnrollmentRequest.fromServer(
          MapEntry(
            notification.key,
            notification.value,
          ),
        );
        if (!_enrollmentRequestsController!.isClosed) {
          _enrollmentRequestsController!.add(enrollmentRequest);
        }
      } catch (e, st) {
        debugPrint(e.toString());
        debugPrint(st.toString());
        _enrollmentRequestsController!.addError(UnexpectedResponseException(e.toString()));
      }
    });
  }

  Future<void> dispose() async {
    await _newRequestsSubscription?.cancel();
    await _enrollmentRequestsController?.close();
  }

  Stream<EnrollmentRequest>? get enrollmentRequests => _enrollmentRequestsController?.stream;

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
      throw UnexpectedResponseException(rawResponse ?? 'No response from server');
    }
    final rawData = rawResponse.substring(rawResponse.indexOf('data:') + 5);
    final data = jsonDecode(rawData) as Map<String, dynamic>;
    // TODO: Filter out `firstApp` enrolment
    final enrollmentRequests = data.entries.map(EnrollmentRequest.fromServer).toList();
    return enrollmentRequests;
  }

  Future<bool> isMasterKey() async {
    throw UnimplementedError();
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
    if (!_isSppValid(spp)) {
      throw InvalidSppException();
    }

    final command = 'otp:put:$spp:ttl:${sppExpiry.inMilliseconds}\n';

    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final response = await atLookup.executeCommand(command, auth: true);
    // TODO: Add error handling
    debugPrint(response);
  }

  /// Get the OTP from the server.
  ///
  /// If an spp is set, the server will return the spp,
  /// otherwise it will return a randomly generated OTP.
  ///
  /// [optExpiry] Defaults to 5 minutes.
  Future<String> generateOtp({Duration optExpiry = _kDefaultExpiry}) async {
    final command = 'otp:get:ttl:${optExpiry.inMilliseconds}\n';

    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final response = await atLookup.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5);
      assert(otp.length >= 6, 'OTP should be 6 or more characters');
      return otp;
    } else {
      throw OtpGenerationException(response ?? 'No response from server');
    }
  }

  /// Approve the given [enrollmentRequest].
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
      throw FailedToApproveException();
    }
    return;
  }

  /// Deny the given [enrollmentRequest].
  Future<void> deny(EnrollmentRequest enrollmentRequest) async {
    // Get the lookup service from the secondary server.
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await atAuthBase.atEnrollment(atSign).deny(
          EnrollmentRequestDecision.denied(
            enrollmentRequest.enrollmentId,
          ),
          atLookup,
        );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.denied) {
      throw FailedToDenyException();
    }
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
  });
  // TODO: Add an asssert to confirm that if the status is pending there is an encryptedAPKAMSymmetricKey.

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
      status: getEnrollStatusFromString(entry.value['status'] as String),
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
        other.namespacePermissions == namespacePermissions;
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
/// The string representation of the permission is `namespace: {ns1: rw, ns2: r}` where read is `r` and write is `w`.
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
