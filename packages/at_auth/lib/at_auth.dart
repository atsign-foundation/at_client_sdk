/// The [AtAuth] package contains common logic for onboarding/authenticating an atSign to a secondary server
library;

export 'src/at_auth.dart';

// Contains models related to onboarding and authentication requests, and the
// AtAuthSession that authenticate/onboard hand back.
export 'src/auth/models/at_auth_requests.dart';
export 'src/auth/models/at_auth_session.dart';
// PKAM signing strategies (AtPkamSigner implementations) for at_lookup.
export 'src/auth/pkam_signers.dart';
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

// The approving app's decision on an enrollment request: EnrollmentApproval,
// EnrollmentDenial or EnrollmentRevocation, built via the
// EnrollmentRequestDecision factories.
export 'src/enroll/models/enrollment_request_decision.dart';

export 'src/exception/at_auth_exceptions.dart';
export 'src/keys/at_keys.dart';
// AtKeysMaterial is the API-level typed key material — the only type
// AtKeys's API deals in. It owns its own JSON (de)serialization; the
// document-level `keys[]` grouping/validation lives in
// parseAtKeysDocument/encodeAtKeysDocument, also exported here.
export 'src/keys/serialization/atkey_material.dart';
export 'src/keys/serialization/assurance.dart';
export 'src/keys/serialization/passphrase_envelope.dart';
export 'src/keys/io/at_keys_io.dart';
export 'src/keys/io/file_io.dart';
export 'src/keys/io/ephemeral_io.dart';

/// Classes for registrar services
export 'src/registrar/registrar.dart';
export 'src/registrar/registrar_service.dart';
