/// The [AtAuth] package contains common logic for onboarding/authenticating an atSign to a secondary server
library;

import 'package:at_auth/src/auth_interface.dart';
import 'package:at_auth/src/auth_interface_impl.dart';

export 'src/at_auth_base.dart';
export 'src/auth/at_auth_request.dart';
export 'src/auth/at_auth_response.dart';
export 'src/auth_constants.dart';
// Contains method related to submit, approve and deny an enrollment.
export 'src/enroll/at_enrollment_base.dart';
// Contains fields related to enrollment response received from the secondary server
export 'src/enroll/at_enrollment_response.dart';
// The abstract class contains fields related to enrollment request
export 'src/enroll/base_enrollment_request.dart';
/// The class contains fields to submit enrollment request for APKAM keys which generate keys for
/// an application with restricted access to the namespaces.
export 'src/enroll/enrollment_request.dart';
/// This class serves as the entity responsible for either approving or denying an enrollment request
export 'src/enroll/enrollment_request_decision.dart';
/// The class stores enrollment request details. It notifies the approving app upon receiving a
/// request from the requesting app, for approval or denial.
export 'src/enroll/enrollment_server_response.dart';
export 'src/exception/at_auth_exceptions.dart';
export 'src/keys/at_auth_keys.dart';
export 'src/onboard/at_onboarding_request.dart';
export 'src/onboard/at_onboarding_response.dart';

/// Global constant to access [AtAuthInterface].
///
/// Serves as the primary entry point to access public methods in at_auth package.
final AtAuthInterface atAuthBase = AtAuthInterfaceImpl();
