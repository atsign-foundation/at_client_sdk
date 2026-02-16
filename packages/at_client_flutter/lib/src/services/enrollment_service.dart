import 'dart:async';
import 'dart:convert';

import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/at_client_flutter.dart';

import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

class FlutterEnrollmentService {
  final AtSignLogger _logger = AtSignLogger('FlutterEnrollmentService');
  final AtEnrollment _atEnrollment = AtEnrollment.create();
  final KeychainStorage _keychainStorage = KeychainStorage();
  final KeychainAtKeysIo _keychainAtKeysIo = KeychainAtKeysIo();

  AtClient get atClient => AtClientManager.getInstance().atClient;

  // Used for updating realtime ui
  StreamController<EnrollmentServerResponse>? _enrollmentRequestsController =
      StreamController<EnrollmentServerResponse>.broadcast();
  StreamSubscription? _newRequestsSubcription;

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

    //If the atEnrollmentResponse contains atAuthKeys, it means it isn't a first time enrollment.
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
    if (_enrollmentRequestsController!.onListen == null) {
      _enrollmentRequestsController!.onListen = _listenForNewRequest;
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

  Future<List<EnrollmentServerResponse>> list(
      List<EnrollmentStatus> filters, AtLookUp atLookUp,
      {String? drx, String? arx}) async {
    return await _atEnrollment.list(filters, atLookUp, arx: arx, drx: drx);
  }

  Future<void> awaitApproval(AtEnrollmentResponse response) async {
    await _atEnrollment.waitForApproval(response);
  }

  void _listenForNewRequest() {
    final stream = atClient.notificationService.subscribe(
      regex: r'r.*\.new\.enrollments\.__manage',
      shouldDecrypt: false,
    );

    _newRequestsSubcription = stream.listen((AtNotification noti) async {
      try {
        _logger.info('Enrollment Request with id ${noti.key} received');
        final enrollmentRequest = EnrollmentServerResponse.fromServer(MapEntry(
          noti.key,
          jsonDecode(noti.value!),
        ));
        if (!_enrollmentRequestsController!.isClosed) {
          _enrollmentRequestsController!.add(enrollmentRequest);
        }
      } catch (e, st) {
        _logger.severe('Failed to process new enrollment request.', e, st);
        _enrollmentRequestsController!.addError(Exception(e.toString()));
      }
    });
  }

  Future<void> dispose() async {
    await _newRequestsSubcription?.cancel();
    _newRequestsSubcription = null;
    await _enrollmentRequestsController!.close();
    _enrollmentRequestsController = null;
  }
}
