/// The [AtAuth] package contains common logic for onboarding/authenticating an atSign to a secondary server
library;

export 'src/at_auth.dart';
export 'src/auth_constants.dart';

// Contains models related to onboarding and authentication requests and responses.
export 'src/auth/models/at_auth_requests.dart';
export 'src/auth/models/at_auth_responses.dart';
// Contains method related to submit, approve and deny an enrollment.
export 'src/enroll/at_enrollment.dart';
// Contains fields related to enrollment response received from the secondary server
export 'src/enroll/models/at_enrollment_response.dart';
// Contains the NamespacePermission model
export 'src/enroll/models/namespace_permission.dart';
// Contains the Otp model
export 'src/enroll/models/otp.dart';
// The abstract class contains fields related to enrollment request
/// The class contains fields to submit enrollment request for APKAM keys which generate keys for
/// an application with restricted access to the namespaces.
export 'src/enroll/models/at_enrollment_request.dart';

/// This class serves as the entity responsible for either approving or denying an enrollment request
export 'src/enroll/models/enrollment_request_decision.dart';

/// The class stores enrollment request details. It notifies the approving app upon receiving a
/// request from the requesting app, for approval or denial.
export 'src/exception/at_auth_exceptions.dart';
export 'src/keys/at_keys_legacy.dart';
export 'src/keys/at_keys_io.dart';
export 'src/keys/at_keys_io_impl.dart';

/// Classes for registrar services
export 'src/registrar/registrar.dart';
export 'src/registrar/registrar_service.dart';
