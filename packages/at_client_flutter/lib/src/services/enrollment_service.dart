import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// {@template flutter_enrollment_service}
/// A service class for managing enrollment requests in a Flutter environment.
/// {@endtemplate}
class FlutterEnrollmentService {
  /// {@macro flutter_enrollment_service}
  ///
  /// Pass [atClient] to work against a client the app owns; with none, the
  /// service uses [AtClientManager]'s current one as it always has.
  FlutterEnrollmentService({AtClient? atClient}) : _atClient = atClient {
    _logger.info('Initialising FlutterEnrollmentService');
    _enrollmentRequestsController!.onListen = _listenForNewRequests;
  }

  final AtClient? _atClient;

  final AtSignLogger _logger = AtSignLogger('FlutterEnrollmentService');
  final AtEnrollment _atEnrollment = AtEnrollment.create();

  @visibleForTesting
  KeychainStorage keychainStorage = KeychainStorage();

  @visibleForTesting
  KeychainAtKeysIo keychainAtKeysIo = KeychainAtKeysIo();

  @visibleForTesting
  AtClient? atClientOverride;

  /// Instance of [AtClient] for the current atSign
  AtClient get atClient =>
      atClientOverride ?? _atClient ?? AtClientManager.getInstance().atClient;

  static const _kDefaultExpiry = Duration(minutes: 5);

  StreamController<ServerEnrollmentRequest>? _enrollmentRequestsController =
      StreamController<ServerEnrollmentRequest>.broadcast();
  StreamSubscription? _newRequestsSubscription;

  /// Stream of progress events during enrollment operations
  Stream<ProgressEvent> get progressStream => _atEnrollment.progressStream;

  /// Submit an enrollment request to the secondary server
  ///
  ///   [request] - [EnrollmentRequest] containing enrollment details such as
  ///   atSign, namespaces and enrollment metadata
  ///
  ///   [waitForApproval] - Optional parameter to wait until the enrollment
  ///   request is approved on the server
  ///
  /// Returns [AtEnrollmentResponse] which contains the enrollment id, status
  /// and generated auth keys when available
  Future<AtEnrollmentResponse> enroll(
    EnrollmentRequest request, {
    bool waitForApproval = false,
  }) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    // NOTE: an enrolment request is submitted unauthenticated — the requesting
    // device holds no credential to authenticate with yet.
    final AtLookUp atLookup = AtLookUp.withSecureSocket(
      atSign: request.atSign,
      rootDomain: request.rootDomain,
      transport: secureSocketTransport(SecureSocketConfig()),
      authenticator: null,
    );
    try {
      atEnrollmentResponse = await _atEnrollment.submit(request, atLookup);
    } catch (e, s) {
      throw Exception('Enrollment failed: $e \n $s');
    } finally {
      // Always close the connection, including when submit() throws (a timeout
      // or a network failure) — otherwise the lookup's connection leaks.
      await atLookup.close();
    }

    if (atEnrollmentResponse.atAuthKeys != null) {
      EnrollmentData enrollmentData = EnrollmentData(
        atEnrollmentResponse.enrollmentId,
        atEnrollmentResponse.atAuthKeys!,
        DateTime.now().toUtc().microsecondsSinceEpoch,
        namespace: (request is AtEnrollmentRequest) ? request.namespaces : null,
      );
      await keychainStorage.writeEnrollmentData(
        atSign: request.atSign,
        enrollmentData: enrollmentData,
      );
    }
    if (waitForApproval) {
      await awaitApproval(atEnrollmentResponse);
    }
    return atEnrollmentResponse;
  }

  /// Approve a pending enrollment request
  ///
  ///   [request] - [EnrollmentRequestDecision] containing the enrollment id,
  ///   atSign and approval decision details
  ///
  ///   [atLookUp] - [AtLookUp] instance used to communicate with the secondary
  ///   server, using an atLookUp as we should be authenticated.
  ///
  /// Returns [AtEnrollmentResponse] containing the status of the approval and
  /// auth keys for the approved enrollment
  Future<AtEnrollmentResponse> approve(
    EnrollmentRequestDecision request,
    AtLookUp atLookUp,
  ) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      if (!await keychainStorage.validateEnrollment(request.atSign)) {
        throw Exception('Invalid enrollment');
      }
      // NOTE: approving also seals this atSign's secrets to the enrollee's key
      // package, which only the client's enrollment service does — an approval
      // made through at_auth alone can authenticate but decrypt nothing.
      atEnrollmentResponse = await atClient.enrollmentService!.approve(request);
      // NOTE: the approver holds no enrollee key material — approve() answers
      // with the id and status, and the enrollee files its own keys.
      final approvedKeys = atEnrollmentResponse.atAuthKeys;
      if (approvedKeys != null) {
        await keychainAtKeysIo.write(request.atSign, approvedKeys);
      }
      await _forgetPendingRequest(request.atSign);
      // ignore: experimental_member_use
    } on EnrollmentConveyanceException {
      // NOTE: the approval itself succeeded and only the conveyance to the new
      // device failed, so the enrollment is live but cannot decrypt — the
      // pending record still has to go.
      await _forgetPendingRequest(request.atSign);
      rethrow;
    } catch (e) {
      throw Exception('Enrollment failed: $e');
    } finally {
      await atLookUp.close();
    }
    return atEnrollmentResponse;
  }

  /// Drop the local record of a request that has now been decided.
  ///
  /// Never throws: the atServer has already recorded the decision by the time
  /// this runs, so a keychain failure costs only a pending row that lingers
  /// until [KeychainStorage.validateEnrollment] expires it.
  Future<void> _forgetPendingRequest(String atSign) async {
    try {
      await keychainStorage.deleteEnrollmentData(atSign);
    } catch (e) {
      _logger.warning(
        'Decided the enrollment for $atSign but could not drop its pending '
        'record; it will linger until it expires: $e',
      );
    }
  }

  /// Deny a pending enrollment request
  ///
  ///   [request] - [EnrollmentRequestDecision] containing the enrollment id,
  ///   atSign and denial decision details
  ///
  ///   [atLookUp] - [AtLookUp] instance used to communicate with the secondary
  ///   server
  ///
  /// Returns [AtEnrollmentResponse] containing the status of the denied
  /// enrollment request
  Future<AtEnrollmentResponse> deny(
    EnrollmentRequestDecision request,
    AtLookUp atLookUp,
  ) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse = await _atEnrollment.deny(request, atLookUp);
    } catch (e) {
      throw Exception('Denial failed: $e');
    } finally {
      await atLookUp.close();
    }
    return atEnrollmentResponse;
  }

  /// Revoke an existing enrollment
  ///
  ///   [request] - [EnrollmentRequestDecision] containing the enrollment id,
  ///   atSign and revocation details
  ///
  ///   [atLookUp] - [AtLookUp] instance used to communicate with the secondary
  ///   server
  ///
  /// Returns [AtEnrollmentResponse] containing the status of the revoked
  /// enrollment
  Future<AtEnrollmentResponse> revoke(
    EnrollmentRequestDecision request,
    AtLookUp atLookUp,
  ) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    try {
      atEnrollmentResponse = await _atEnrollment.revoke(request, atLookUp);
    } catch (e) {
      throw Exception('Revocation failed: $e');
    } finally {
      await atLookUp.close();
    }
    return atEnrollmentResponse;
  }

  /// Listen for enrollment requests received from the server
  ///
  ///   [statusFilters] - Optional list of [EnrollmentStatus] values used to
  ///   filter the returned enrollment requests
  ///
  /// Returns a [Stream] of [EnrollmentServerResponse] values matching the
  /// provided filters
  Stream<EnrollmentServerResponse> getEnrollments({
    List<EnrollmentStatus>? statusFilters,
  }) {
    return _enrollmentRequestsController!.stream.map((event) => event).where((
      event,
    ) {
      if (statusFilters == null) return true;
      return statusFilters.contains(event.status);
    });
  }

  /// List enrollments from the secondary server
  ///
  ///   [filters] - List of [EnrollmentStatus] values used to filter server
  ///   results
  ///
  ///   [atLookUp] - [AtLookUp] instance used to communicate with the secondary
  ///   server
  ///
  ///   [drx] - Optional device regex filter
  ///
  ///   [arx] - Optional app regex filter
  ///
  /// Returns a [List] of [EnrollmentServerResponse] objects matching the
  /// filters
  Future<List<EnrollmentServerResponse>> list(
    List<EnrollmentStatus> filters,
    AtLookUp atLookUp, {
    String? drx,
    String? arx,
  }) async {
    return await _atEnrollment.list(filters, atLookUp, arx: arx, drx: drx);
  }

  /// Wait for a submitted enrollment request to be approved
  ///
  ///   [response] - [AtEnrollmentResponse] returned from an earlier enrollment
  ///   submission
  Future<void> awaitApproval(AtEnrollmentResponse response) async {
    await _atEnrollment.waitForApproval(response);
  }

  /// Check if the current atSign has manager permissions.
  Future<bool> isManagerKey() async {
    final atLookUp = atClient.getRemoteSecondary()!.atLookUp;
    final enrollments = await list([], atLookUp);
    final hasManagePermission = enrollments.any(
      (e) =>
          e.namespacePermissions.any(
            (p) => p.namespace == '__manage' && p.write && p.read,
          ) &&
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
    await keychainStorage.saveSpp(atClient.getCurrentAtSign()!, otp);
    return otp;
  }

  /// Get the active SPP from the keychain.
  ///
  /// Returns `null` if no SPP is set or the last SPP has expired.
  Future<SppData?> getActiveSpp() =>
      keychainStorage.getActiveSpp(atClient.getCurrentAtSign()!);

  /// Get all active (non-expired) SPPs from the keychain.
  Future<List<SppData>> getAllSpps() =>
      keychainStorage.getAllSpps(atClient.getCurrentAtSign()!);

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

    _newRequestsSubscription = stream.listen((
      AtNotification notification,
    ) async {
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
          _enrollmentRequestsController!.addError(
            UnexpectedResponseException(e.toString()),
          );
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
