library at_client_mobile;

export 'package:at_client/at_client.dart';

@Deprecated('Use AtClientMobile.authService')
export 'src/at_client_auth.dart';
export 'src/at_client_mobile_base.dart';
// Since "src/at_client_service" is deprecated and "BackupKeyConstants" are being used by "at_backupkey_flutter" moved them
// to "src/auth_constants.dart"
@Deprecated('Use AtClientMobile.authService')
export 'src/at_client_service.dart' hide BackupKeyConstants;
// Contains public methods to handle the onboarding, authentication, and enrollment submission for an atSign
export 'src/auth/at_auth_service.dart';
@Deprecated('Use AtClientMobile.authService')
// TODO: Remove this is next major release
export 'src/auth/at_auth_service_impl.dart';
// BackupKeyConstants are used in "at_backupkey_flutter" package. Hence exposing only fields in BackupKeyFlutter
export 'src/auth_constants.dart' show BackupKeyConstants;
// Contains the enrollment details
export 'src/enrollment/enrollment_info.dart';
export 'src/keychain_manager.dart';
export 'src/onboarding_status.dart';
