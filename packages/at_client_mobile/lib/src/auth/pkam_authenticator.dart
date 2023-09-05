import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_lookup/at_lookup.dart';

import 'at_authenticator.dart';

class PkamAuthenticator implements AtAuthenticator {
  AtLookUp _atLookup;
  PkamAuthenticator(this._atLookup);

  @override
  Future<AtAuthResponse> authenticate(String atSign,
      {String? enrollmentId}) async {
    var authResult = AtAuthResponse(atSign);
    try {
      bool pkamResult =
          await _atLookup.pkamAuthenticate(enrollmentId: enrollmentId);
      authResult.isSuccessful = pkamResult;
    } on UnAuthenticatedException catch (e) {
      var errorCode = _getErrorCode(e);
      throw AtClientException(_getErrorCode(e),
          'pkam auth failed for $atSign - ${error_description[errorCode]}');
    }
    return authResult;
  }

  String _getErrorCode(AtException e) {
    //#TODO implement
    return '';
  }
}
