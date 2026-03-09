import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// {@template flutter_enrollment_service}
/// A service class for managing enrollment requests in a Flutter environment.
/// {@endtemplate}
class FlutterEnrollmentService {
  /// {@macro flutter_enrollment_service}
  FlutterEnrollmentService();

  final AtSignLogger _logger = AtSignLogger('FlutterEnrollmentService');
  final AtEnrollment _atEnrollment = AtEnrollment.create();
  final KeychainStorage _keychainStorage = KeychainStorage();
  final SppKeychainData _sppKeychainData = SppKeychainData();

  AtClient get atClient => AtClientManager.getInstance().atClient;

  static const _kDefaultExpiry = Duration(minutes: 5);

  StreamController<ServerEnrollmentRequest>? _enrollmentRequestsController;
  StreamSubscription? _newRequestsSubscription;

  /// Call this method before any other methods.
  ///
  /// Sets up the subscription to the server for new enrollment requests.
  void init() {
    _logger.info('Initialising FlutterEnrollmentService');
    _enrollmentRequestsController ??=
        StreamController<ServerEnrollmentRequest>.broadcast();
    _enrollmentRequestsController!.onListen = _listenForNewRequests;
  }

  void _listenForNewRequests() {
    // Set up a stream to listen for new enrollment requests.
    final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    // Add the new requests to the stream controller.
    _newRequestsSubscription =
        stream.listen((AtNotification notification) async {
      try {
        _logger.info('Enrollment request with id ${notification.key} received');
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
        _logger.severe('Failed to process new enrollment request.', e, st);
        if (!_enrollmentRequestsController!.isClosed) {
          _enrollmentRequestsController!
              .addError(UnexpectedResponseException(e.toString()));
        }
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
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;

    final enrollmentResponses = await _atEnrollment.list(
      statusFilters,
      atLookup,
    );

    final enrollmentRequests = enrollmentResponses.map((response) {
      return ServerEnrollmentRequest(
        enrollmentId: response.enrollmentId,
        appName: response.appName,
        deviceName: response.deviceName,
        status: response.status,
        namespacePermissions: response.namespace
            .map((p) => NamespacePermission(
                  namespace: p.namespace,
                  read: p.read,
                  write: p.write,
                ))
            .toList(),
        encryptedAPKAMSymmetricKey: response.encryptedAPKAMSymmetricKey,
      );
    }).toList();

    _logger.info('Found ${enrollmentRequests.length} enrollmentRequests');
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
    _logger.info('Has manage permissions: $hasManagePermission');
    return hasManagePermission;
  }

  /// Set a semi-permanent passcode/OTP.
  ///
  /// This is used to approve enrollments.
  /// It can be useful to set an spp if enrolling many devices at once.
  /// The SPP is saved to the keychain so it can be retrieved later.
  ///
  /// The [spp] must be alphanumeric and exactly 6 characters long.
  ///
  /// [sppExpiry] Defaults to 5 minutes.
  Future<Otp> setSpp({
    required String spp,
    Duration sppExpiry = _kDefaultExpiry,
  }) async {
    _logger.finer(
      'Setting spp to $spp expiring in ${sppExpiry.inSeconds}s',
    );
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final otp = await _atEnrollment.setSpp(spp, atLookup, expiry: sppExpiry);
    _logger.info('SPP set on the server');
    await _sppKeychainData.save(atClient.getCurrentAtSign()!, otp);
    return otp;
  }

  /// Get the active SPP from the keychain.
  ///
  /// Returns `null` if no SPP is set or the last SPP has expired.
  Future<Otp?> getActiveSpp() =>
      _sppKeychainData.getActive(atClient.getCurrentAtSign()!);

  /// Get the OTP from the server.
  ///
  /// If an spp is set, the server will return the spp,
  /// otherwise it will return a randomly generated OTP.
  ///
  /// [optExpiry] Defaults to 5 minutes.
  ///
  /// Throws [OtpGenerationException] if the OTP could not be generated.
  Future<Otp> generateOtp({Duration optExpiry = _kDefaultExpiry}) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    return _atEnrollment.generateOtp(atLookup, expiry: optExpiry);
  }

  /// Approve the given [enrollmentRequest].
  ///
  /// Throws [FailedToApproveException] if the request was not approved.
  Future<void> approve(ServerEnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;

    final enrollmentOutcome = await _atEnrollment.approve(
      EnrollmentRequestDecision.approved(
        enrollmentId: enrollmentRequest.enrollmentId,
        apkamSymmetricKey: AtBytes.fromString(
          enrollmentRequest.encryptedAPKAMSymmetricKey!,
        ),
        atSign: atSign,
      ),
      atLookup,
    );

    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.approved) {
      _logger.severe(
        'Failed to approve enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToApproveException();
    }
    _logger.info(
        'Enrollment request with id ${enrollmentRequest.enrollmentId} approved');
    return;
  }

  /// Deny the given [enrollmentRequest].
  ///
  /// Throws [FailedToDenyException] if the request was not denied.
  Future<void> deny(ServerEnrollmentRequest enrollmentRequest) async {
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentOutcome = await _atEnrollment.deny(
      EnrollmentRequestDecision.denied(
        enrollmentRequest.enrollmentId,
        atSign,
      ),
      atLookup,
    );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.denied) {
      _logger.severe(
        'Failed to deny enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToDenyException();
    }
    _logger.info(
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
    final enrollmentOutcome = await _atEnrollment.revoke(
      EnrollmentRequestDecision.revoked(
        enrollmentRequest.enrollmentId,
        atSign,
      ),
      atLookup,
    );
    if (enrollmentOutcome.enrollStatus != EnrollmentStatus.revoked) {
      _logger.severe(
        'Failed to revoke enrollment request with id ${enrollmentRequest.enrollmentId}. Status: ${enrollmentOutcome.enrollStatus}',
      );
      throw FailedToRevokeException();
    }
    _logger.info(
        'Enrollment request with id ${enrollmentRequest.enrollmentId} revoked');
    return;
  }

  Future<AtEnrollmentResponse> enroll(EnrollmentRequest request,
      {bool waitForApproval = false}) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    AtLookUp atLookup = AtLookupImpl(request.atSign,
        request.rootDomain.rootDomain, request.rootDomain.rootPort);
    try {
      atEnrollmentResponse = await _atEnrollment.submit(request, atLookup);
    } catch (e, s) {
      throw Exception('Enrollment failed: $e \n $s');
    }
    await atLookup.close();

    if (atEnrollmentResponse.atAuthKeys != null) {
      EnrollmentData enrollmentData = EnrollmentData(
          atEnrollmentResponse.enrollmentId,
          atEnrollmentResponse.atAuthKeys!,
          DateTime.now().toUtc().microsecondsSinceEpoch,
          namespace:
              (request is AtEnrollmentRequest) ? request.namespaces : null);
      await _keychainStorage.writeEnrollmentData(
          atSign: request.atSign, enrollmentData: enrollmentData);
    }
    if (waitForApproval) {
      await awaitApproval(atEnrollmentResponse);
    }
    return atEnrollmentResponse;
  }

  Future<void> awaitApproval(AtEnrollmentResponse response) async {
    await _atEnrollment.waitForApproval(response);
  }

  Stream<ProgressEvent> get progressStream => _atEnrollment.progressStream;
}
