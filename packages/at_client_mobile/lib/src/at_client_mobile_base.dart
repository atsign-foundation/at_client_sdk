import 'package:at_client/at_client.dart';
import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_auth_service_impl.dart';

/// The Base class to expose the AtClientMobile services.
class AtClientMobileBase {
  /// Returns an instance of [AtAuthService]
  ///
  /// Example:
  ///
  ///  AtAuthService authService = AtClientMobile.authService(_atsign!, _atClientPreference);
  AtAuthService authService(
      String atSign, AtClientPreference atClientPreference) {
    return AtAuthServiceImpl(atSign, atClientPreference);
  }
}
