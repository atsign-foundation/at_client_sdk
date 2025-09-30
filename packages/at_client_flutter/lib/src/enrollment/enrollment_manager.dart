import 'dart:convert';

import 'package:at_client_flutter/src/enrollment/enrollment_info.dart';
import 'package:at_client_flutter/src/keychain/keychain_storage.dart';

class EnrollmentManager {
  final _maxEnrollmentAuthenticationRetryInHours = 48;

  final KeyChainStorage keyChainStorage = KeyChainStorage();
  // Enrollment related functions
  Future<void> writeToEnrollmentStore(
      String atSign, EnrollmentInfo enrollmentInfo) async {
    final store = await keyChainStorage.getEnrollmentStorage(atSign);
    await keyChainStorage.writeDataToStore(
        store: store, data: jsonEncode(enrollmentInfo));
  }

  Future<EnrollmentInfo> readFromEnrollmentStore(String atSign) async {
    final store = await keyChainStorage.getEnrollmentStorage(atSign);
    var data = await keyChainStorage.readDataFromStore(store: store);
    return EnrollmentInfo.fromJson(jsonDecode(data!));
  }

  Future<void> deleteEnrollmentStore(String atSign) async {
    final store = await keyChainStorage.getEnrollmentStorage(atSign);
    await store.delete();
  }

  /// Validates if the enrollment is still valid based on the submission time.
  Future<bool> validateEnrollment(String atSign) async {
    try {
      var data = await readFromEnrollmentStore(atSign);
      if (DateTime.now()
              .toUtc()
              .difference(DateTime.fromMillisecondsSinceEpoch(
                  data.enrollmentSubmissionTimeEpoch))
              .inHours >=
          _maxEnrollmentAuthenticationRetryInHours) {
        await deleteEnrollmentStore(atSign);
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
