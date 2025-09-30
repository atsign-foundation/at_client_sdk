import 'package:at_auth/at_auth.dart';
import 'package:at_client_flutter/src/enrollment/enrollment_info.dart';
import 'package:at_client_flutter/src/enrollment/enrollment_manager.dart';
import 'package:at_client_flutter/src/keychain/keychain_io_impl.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';

class EnrollmentService {
  final AtEnrollment _atEnrollment = AtEnrollment.create();
  final _enrollmentStore = EnrollmentManager();
  final KeychainAtKeysIo _keychainAtKeysIo = KeychainAtKeysIo();

  Stream<ProgressEvent> get progressStream => _atEnrollment.progressStream;

  Future<AtEnrollmentResponse> enroll(EnrollmentRequest request) async {
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
      EnrollmentInfo enrollmentInfo = EnrollmentInfo(
        atEnrollmentResponse.enrollmentId,
        atEnrollmentResponse.atAuthKeys!,
        DateTime.now().toUtc().microsecondsSinceEpoch,
        (request is AtEnrollmentRequest) ? request.namespaces : null,
      );
      await _enrollmentStore.writeToEnrollmentStore(
          request.atSign, enrollmentInfo);
    }
    await _atEnrollment.waitForApproval(atEnrollmentResponse);

    return atEnrollmentResponse;
  }

  Future<AtEnrollmentResponse> approve(
      EnrollmentRequestDecision request, AtLookUp atLookUp) async {
    AtEnrollmentResponse? atEnrollmentResponse;

    try {
      if (!await _enrollmentStore.validateEnrollment(request.atSign)) {
        throw Exception('Invalid enrollment');
      }
      atEnrollmentResponse = await _atEnrollment.approve(request, atLookUp);
      _keychainAtKeysIo.write(request.atSign, atEnrollmentResponse.atAuthKeys);
      _enrollmentStore.deleteEnrollmentStore(request.atSign);
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
}
