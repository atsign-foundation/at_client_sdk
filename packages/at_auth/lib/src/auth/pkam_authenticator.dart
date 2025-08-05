import 'package:at_auth/src/auth/at_auth_response.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

class PkamAuthenticator {
  final String _atSign;
  final AtLookUp _atLookup;
  PkamAuthenticator(this._atSign, this._atLookup);

  Future<AtAuthResponse> authenticate({String? enrollmentId}) async {
    var authResult = AtAuthResponse(_atSign);
    try {
      bool pkamResult =
          await _atLookup.pkamAuthenticate(enrollmentId: enrollmentId);
      authResult.isSuccessful = pkamResult;
    } on UnAuthenticatedException catch (e) {
      throw UnAuthenticatedException(
          'pkam auth failed for $_atSign - ${e.toString()}');
    }
    return authResult;
  }
}
