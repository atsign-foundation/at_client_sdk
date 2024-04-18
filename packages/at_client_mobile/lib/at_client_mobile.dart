library at_client_mobile;

export 'package:at_client/at_client.dart';

@Deprecated('Use AtClientMobile.authService')
export 'src/at_client_auth.dart';
export 'src/at_client_mobile_base.dart';
@Deprecated('Use AtClientMobile.authService')
export 'src/at_client_service.dart';
// Contains public methods to handle the onboarding, authentication, and enrollment submission for an atSign
export 'src/auth/at_auth_service.dart';
@Deprecated('Use AtClientMobile.authService')
// TODO: Remove this is next major release
export 'src/auth/at_auth_service_impl.dart';
// Contains the enrollment details
export 'src/enrollment/enrollment_info.dart';
export 'src/keychain_manager.dart';
export 'src/onboarding_status.dart';
