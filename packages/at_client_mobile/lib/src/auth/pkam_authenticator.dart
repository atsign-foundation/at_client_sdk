import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_lookup/at_lookup.dart';

import 'at_authenticator.dart';

class PkamAuthenticator implements AtAuthenticator {
  AtLookUp _atLookup;
  PkamAuthenticator(this._atLookup);

  @override
  Future<AtAuthResponse> authenticate(String atSign) async {
    var authResult = AtAuthResponse(atSign);
    try {
      bool pkamResult = await _atLookup.pkamAuthenticate();
      authResult.isSuccessful = pkamResult;
    } on UnAuthenticatedException catch (e) {
      authResult.atClientException = AtClientException(
          error_codes['UnAuthenticatedException'],
          'pkam auth failed for $atSign - ${e.toString()}');
    }
    return authResult;
  }
}
