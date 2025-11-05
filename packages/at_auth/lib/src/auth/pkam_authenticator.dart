import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class PkamAuthenticator {
  PkamAuthenticator();

  Future<bool> authenticate(String atSign, AtLookUp atLookup, {String? enrollmentId}) async {
    try {
      return await atLookup.pkamAuthenticate(enrollmentId: enrollmentId);
    } catch (e) {
      throw UnAuthenticatedException(
          'pkam auth failed for $atSign - ${e.toString()}');
    }
  }
}