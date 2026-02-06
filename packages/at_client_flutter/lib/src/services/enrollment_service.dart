import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';

import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

import '../keychain/keychain_data.dart';
import '../keychain/keychain_storage.dart';

class FlutterEnrollmentService {
  final AtEnrollment _atEnrollment = AtEnrollment.create();
  final KeychainStorage _keychainStorage = KeychainStorage();
  final KeychainAtKeysIo _keychainAtKeysIo = KeychainAtKeysIo();

  Stream<ProgressEvent> get progressStream => _atEnrollment.progressStream;
  Future<AtEnrollmentResponse> enroll(EnrollmentRequest request,
      {bool waitForApproval = false}) async {
    AtEnrollmentResponse? atEnrollmentResponse;
    AtLookUp atLookup = AtLookupImpl(request.atSign,
        request.rootDomain.rootDomain, request.rootDomain.rootPort);
    try {
      atEnrollmentResponse = await _atEnrollment.submit(request, atLookup);
    } catch (e) {
      throw Exception('Enrollment failed: $e');
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
      await _atEnrollment.waitForApproval(atEnrollmentResponse);
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

  Future<List<EnrollmentServerRequest>> list(
      List<EnrollmentStatus> filters, AtLookUp atLookUp,
      {String? drx, String? arx}) async {
    return await _atEnrollment.list(filters, atLookUp, arx: arx, drx: drx);
  }

  Future<void> waitForApproval(AtEnrollmentResponse response) async {
    await _atEnrollment.waitForApproval(response);
  }
}
