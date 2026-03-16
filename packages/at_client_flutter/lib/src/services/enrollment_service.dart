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
  FlutterEnrollmentService() {
    _logger.info('Initialising FlutterEnrollmentService');
    _enrollmentRequestsController =
        StreamController<ServerEnrollmentRequest>.broadcast();
    _enrollmentRequestsController!.onListen = _listenForNewRequests;
  }

  final AtSignLogger _logger = AtSignLogger('FlutterEnrollmentService');
  final AtEnrollment _atEnrollment = AtEnrollment.create();
  final KeychainStorage _keychainStorage = KeychainStorage();
  final KeychainAtKeysIo _keychainAtKeysIo = KeychainAtKeysIo();

  AtClient get atClient => AtClientManager.getInstance().atClient;

  static const _kDefaultExpiry = Duration(minutes: 5);

  StreamController<ServerEnrollmentRequest>? _enrollmentRequestsController;
  StreamSubscription? _newRequestsSubscription;

  Stream<ProgressEvent> get progressStream => _atEnrollment.progressStream;

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

  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision request, AtLookUp atLookUp) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      if (!await _keychainStorage.validateEnrollment(request.atSign)) {
        throw Exception('Invalid enrollment');
      }
      atEnrollmentResponse = await _atEnrollment.approve(request, atLookUp);
      _keychainAtKeysIo.write(request.atSign, atEnrollmentResponse.atAuthKeys!);
      _keychainStorage.deleteEnrollmentData(request.atSign);
    } catch (e) {
      throw Exception('Enrollment failed: $e');
    }
    await atLookUp.close();
    return atEnrollmentResponse;
  }

  Future<AtEnrollmentResponse> deny(
      EnrollmentRequestDecision request, AtLookUp atLookUp) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse = await _atEnrollment.deny(request, atLookUp);
    } catch (e) {
      throw Exception('Denial failed: $e');
    }
    await atLookUp.close();
    return atEnrollmentResponse;
  }

  Future<AtEnrollmentResponse> revoke(
      EnrollmentRequestDecision request, AtLookUp atLookUp) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse = await _atEnrollment.revoke(request, atLookUp);
    } catch (e) {
      throw Exception('Revocation failed: $e');
    }
    await atLookUp.close();
    return atEnrollmentResponse;
  }

  Stream<EnrollmentServerResponse> getEnrollments(
      {List<EnrollmentStatus>? statusFilters}) {
    return _enrollmentRequestsController!.stream
        .map((event) => event)
        .where((event) {
      if (statusFilters == null) return true;
      return statusFilters.contains(event.status);
    });
  }

  Future<List<EnrollmentServerResponse>> list(
      List<EnrollmentStatus> filters, AtLookUp atLookUp,
      {String? drx, String? arx}) async {
    return await _atEnrollment.list(filters, atLookUp, arx: arx, drx: drx);
  }

  Future<void> awaitApproval(AtEnrollmentResponse response) async {
    await _atEnrollment.waitForApproval(response);
  }

  /// Check if the current atSign has manager permissions.
  Future<bool> isManagerKey() async {
    final atLookUp = atClient.getRemoteSecondary()!.atLookUp;
    final enrollments = await list([], atLookUp);
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
    _logger.finer('Setting spp to $spp expiring in ${sppExpiry.inSeconds}s');
    final atLookup = atClient.getRemoteSecondary()!.atLookUp;
    final otp = await _atEnrollment.setSpp(spp, atLookup, expiry: sppExpiry);
    _logger.info('SPP set on the server');
    await _keychainStorage.saveSpp(atClient.getCurrentAtSign()!, otp);
    return otp;
  }

  /// Get the active SPP from the keychain.
  ///
  /// Returns `null` if no SPP is set or the last SPP has expired.
  Future<SppData?> getActiveSpp() =>
      _keychainStorage.getActiveSpp(atClient.getCurrentAtSign()!);

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

  void _listenForNewRequests() {
    final stream = atClient.notificationService.subscribe(
      regex: r'.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    _newRequestsSubscription =
        stream.listen((AtNotification notification) async {
      try {
        _logger.info('Enrollment request with id ${notification.key} received');
        final enrollmentRequest = ServerEnrollmentRequest.fromServer(
          MapEntry(notification.key, jsonDecode(notification.value!)),
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
}
