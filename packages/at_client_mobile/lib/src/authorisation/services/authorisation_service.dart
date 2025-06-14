import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart' as auth;
import 'package:at_client/at_client_mixins.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_utils/at_logger.dart';
import 'package:biometric_storage/biometric_storage.dart';

/// {@template authorisation_service}
/// A service class for managing enrollment requests.
/// {@endtemplate}
class AuthorisationService with AtClientBindings {
  /// {@macro authorisation_service}
  AuthorisationService();

  @override
  AtClient get atClient => AtClientManager.getInstance().atClient;

  @override
  final AtSignLogger logger = AtSignLogger('AuthorisationService');

  static const _kDefaultExpiry = Duration(minutes: 5);
  static const _kSppRegex = r'[A-Za-z0-9]{6,16}';
  static const _kSppStorageKey = 'spp';

  StreamController<ServerEnrollmentRequest>? _enrollmentRequestsController;
  StreamSubscription? _newRequestsSubscription;

  /// Call this method before any other methods.
  ///
  /// Sets up the subscription to the server for new enrollment requests.
  void init() async {
    logger.info('Initialising AuthorisationService');
    _enrollmentRequestsController ??=
        StreamController<ServerEnrollmentRequest>.broadcast();
    _enrollmentRequestsController!.onListen = _listenForNewRequests;
  }

  void _listenForNewRequests() {
    assert(_enrollmentRequestsController != null,
        'Call AuthorisationService.init() first');
    // Set up a stream to listen for new enrollment requests.
    final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    // Add the new requests to the stream controller.
    _newRequestsSubscription =
        stream.listen((AtNotification notification) async {
      try {
        logger.info('Enrollment request with id ${notification.key} received');
        final enrollmentRequest = ServerEnrollmentRequest.fromServer(
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
        _enrollmentRequestsController!
            .addError(UnexpectedResponseException(e.toString()));
      }
    });
  }

  /// Call this method when the service is no longer needed.
  ///
  /// Closes and cancels all streams and subscriptions.
  Future<void> dispose() async {
    await _newRequestsSubscription?.cancel();
    _newRequestsSubscription = null;
    await _enrollmentRequestsController?.close();
    _enrollmentRequestsController = null;
  }

  /// Stream of all enrollment requests.
  /// Use this for getting real-time updates on new requests.
  Stream<ServerEnrollmentRequest> enrollmentRequests(
      {List<EnrollmentStatus>? statusFilters}) {
    if (_enrollmentRequestsController == null) {
      throw StateError(
          'init() must be called before accessing enrollmentRequests');
    }
    return _enrollmentRequestsController!.stream
        .map((event) => event)
        .where((event) {
      if (statusFilters == null) {
        return true;
      }
      return statusFilters.contains(event.status);
    });
  }

  /// Get enrollment requests. This includes all past and pending requests.
  /// An empty list means no requests could be found.
  /// If passed a list of `EnrollmentStatus`s will only return requests with those statuses.
  /// If [statusFilters] is `null`, will return all requests.
  Future<List<ServerEnrollmentRequest>> getEnrollmentRequests(
      {List<EnrollmentStatus>? statusFilters}) async {
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
      throw UnexpectedResponseException(
          rawResponse ?? 'No response from server');
    }
    final rawData = rawResponse.substring(rawResponse.indexOf('data:') + 5);
    final data = jsonDecode(rawData) as Map<String, dynamic>;
    final enrollmentRequests =
        data.entries.map(ServerEnrollmentRequest.fromServer).toList();
    logger.info('Found ${enrollmentRequests.length} enrollmentRequests');

    // Filter by status if needed.
    if (statusFilters != null) {
      logger.info('Filtering enrollment requests by status: $statusFilters');
      enrollmentRequests.retainWhere((e) => statusFilters.contains(e.status));
      logger.info(
          '${enrollmentRequests.length} enrollment requests after filtering');
    }

    logger.finer('Enrollment Requests: $enrollmentRequests');
    return enrollmentRequests;
  }

  /// Check if the current atSign has manager permissions.
  Future<bool> isManagerKey() async {
    final enrollments = await getEnrollmentRequests();
    // Check if one of the enrollments has read and write permissions for the __manage namespace.
    final hasManagePermission = enrollments.any(
      (e) =>
          e.namespacePermissions
              .any((p) => p.namespace == '__manage' && p.write && p.read) &&
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
  /// The SPP is saved to the keychain so it can be retrieved later.
  ///
  /// The [spp] must be alphanumeric and 6 to 16 characters long.
  ///
  /// [sppExpiry] Defaults to 5 minutes.
  Future<Otp> setSpp({
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

    // Expected response is `data:ok`
    if (response == null || !response.contains('ok')) {
      logger.severe(
          'Invalid response from the server. Expected it to contain `ok`. Response: $response');
      throw OtpGenerationException(response ?? 'No response from server');
    }
    logger.info('SPP set on the server');

    final otp = Otp.fromDuration(value: spp, duration: sppExpiry);

    // Save the spp to the keychain so it can retrieved later if needed.
    try {
      final atSign = atClient.getCurrentAtSign()!;
      final storage = await BiometricStorage().getStorage(
        '$atSign:$_kSppStorageKey',
        options: StorageFileInitOptions(authenticationRequired: false),
      );
      await storage.write(jsonEncode(otp.toJson()));
      logger.info('SPP saved to keychain');
    } catch (e, st) {
      // Choosing to continue execution as at least the spp was set on the server.
      logger.warning('Failed to save SPP to keychain', e, st);
    }

    return otp;
  }

  /// Get the active SPP from the keychain.
  ///
  /// Returns `null` if no SPP is set or the last SPP has expired.
  Future<Otp?> getActiveSpp() async {
    try {
      final atSign = atClient.getCurrentAtSign()!;
      final storage = await BiometricStorage().getStorage(
        '$atSign:$_kSppStorageKey',
        options: StorageFileInitOptions(authenticationRequired: false),
      );
      final data = await storage.read();
      if (data == null) {
        logger.info('No SPP found in keychain');
        return null;
      }
      final otp = Otp.fromJson(jsonDecode(data));
      if (otp.isExpired) {
        logger.info('SPP found in keychain but has expired. Deleting.');
        await storage.delete();
        return null;
      }
      return otp;
    } catch (e, st) {
      logger.severe('Failed to get SPP from keychain', e, st);
      return null;
    }
  }

  /// Get the OTP from the server.
  ///
  /// If an spp is set, the server will return the spp,
  /// otherwise it will return a randomly generated OTP.
  ///
  /// [optExpiry] Defaults to 5 minutes.
  ///
  /// Throws [OtpGenerationException] if the OTP could not be generated.
  Future<Otp> generateOtp({Duration optExpiry = _kDefaultExpiry}) async {
    final command = 'otp:get:ttl:${optExpiry.inMilliseconds}\n';

    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final response = await atLookup.executeCommand(command, auth: true);
    if (response != null && response.startsWith('data:')) {
      final otp = response.substring(response.indexOf('data:') + 5);
      assert(otp.length >= 6, 'OTP should be 6 or more characters');
      logger.finer('OTP generated: $otp');
      return Otp.fromDuration(value: otp, duration: optExpiry);
    } else {
      logger.severe(
          'Invalid response from the server. Expected it to start with `data:`. Response: $response');
      throw OtpGenerationException(response ?? 'No response from server');
    }
  }

  /// Approve the given [enrollmentRequest].
  ///
  /// Throws [FailedToApproveException] if the request was not approved.
  Future<void> approve(ServerEnrollmentRequest enrollmentRequest) async {
    // Get the lookup service from the secondary server.
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome =
        await auth.atAuthBase.atEnrollment(atSign).approve(
              auth.EnrollmentRequestDecision.approved(
                auth.ApprovedRequestDecisionBuilder(
                  enrollmentId: enrollmentRequest.enrollmentId,
                  encryptedAPKAMSymmetricKey:
                      enrollmentRequest.encryptedAPKAMSymmetricKey!,
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
    logger.info(
        'Enrollment request with id ${enrollmentRequest.enrollmentId} approved');
    return;
  }

  /// Deny the given [enrollmentRequest].
  ///
  /// Throws [FailedToDenyException] if the request was not denied.
  Future<void> deny(ServerEnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await auth.atAuthBase.atEnrollment(atSign).deny(
          auth.EnrollmentRequestDecision.denied(
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
    logger.info(
        'Enrollment request with id ${enrollmentRequest.enrollmentId} denied');
    return;
  }

  /// Revoke the given [enrollmentRequest].
  ///
  /// This is for denying a previously approved request.
  /// Throws [FailedToRevokeException] if the request was not revoked.
  Future<void> revoke(ServerEnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await auth.atAuthBase.atEnrollment(atSign).revoke(
          auth.EnrollmentRequestDecision.revoked(
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
    logger.info(
        'Enrollment request with id ${enrollmentRequest.enrollmentId} revoked');
    return;
  }
}
