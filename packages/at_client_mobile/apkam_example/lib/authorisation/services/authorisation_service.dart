import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:flutter/foundation.dart';

class AuthorisationService {
  // I should create a stream controller for this and have a timer to periodically check for new requests.
  // There should also be a method to manually check for new requests (which can be used on app open or foregrounded).

  //? Probably best as a stream of request objects.
  // Empty list means no requests.
  /// Get all enrollment requests. This includes all past and pending requests.
  Future<List<EnrollmentRequest>> getAllEnrollmentRequests(AtClient atClient) async {
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
      throw Exception('Unexpected server response: $rawResponse');
    }
    final rawData = rawResponse.substring(rawResponse.indexOf('data:') + 5);
    final data = jsonDecode(rawData) as Map<String, dynamic>;
    // TODO: Filter out `firstApp` enrolment
    final enrollmentRequests = data.entries.map(EnrollmentRequest.fromServer).toList();
    return enrollmentRequests;
  }

  // Future<bool> isMasterKey() async {
  //   return true;
  // }

  // Future<void> approve(String enrollmentId) async {
  //   final keychainManager = KeyChainManager.getInstance();
  //   final currentAtSign = (await keychainManager.getAtSign())!;
  //   print(currentAtSign);
  //   atAuthBase.atEnrollment('asdf').approve(
  //         EnrollmentRequestDecision.approved(
  //           ApprovedRequestDecisionBuilder(
  //             enrollmentId: 'enrollmentId',
  //             encryptedAPKAMSymmetricKey: 'dummy-encrypted-apkam-symmetric-key',
  //           ),
  //         ),
  //         AtLookupImpl(
  //           currentAtSign,
  //           'dummy-root-domain',
  //           64,
  //           privateKey: await keychainManager.getPkamPrivateKey(currentAtSign),
  //         ),
  //       );
  // }
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
  });

  /// The unique identifier for this enrollment request.
  final String enrollmentId;

  /// The name of the app that is requesting access.
  final String appName;

  /// The name of the device that is requesting access.
  final String deviceName;

  /// The current status of the request.
  final String status; // TODO: Make this an enum.

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
      appName: entry.value['appName'],
      deviceName: entry.value['deviceName'],
      status: entry.value['status'],
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
        other.namespacePermissions == namespacePermissions;
  }

  @override
  int get hashCode =>
      enrollmentId.hashCode ^ appName.hashCode ^ deviceName.hashCode ^ status.hashCode ^ namespacePermissions.hashCode;

  @override
  String toString() {
    return 'EnrollmentRequest(enrollmentId: $enrollmentId, appName: $appName, deviceName: $deviceName, status: $status, namespaces: $namespacePermissions)';
  }
}

/// {@template namespace_permission}
/// Model class representing a namespace permission.
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
