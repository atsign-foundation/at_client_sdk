import 'package:at_client_mobile/at_client_mobile.dart';
import 'package:at_client_mobile/src/auth/at_auth_service_impl.dart';

/// The Base class to expose the AtClientMobile services.
class AtClientMobile {
  /// Returns an instance of [AtAuthService]
  ///
  /// Example:
  ///
  ///  AtAuthService authService = AtClientMobile.authService(_atsign!, _atClientPreference);
  static AtAuthService authService(
      String atSign, AtClientPreference atClientPreference) {
    return AtAuthServiceImpl(atSign, atClientPreference);
  }
}