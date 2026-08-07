/// The [AtAuth] package contains common logic for onboarding/authenticating an atSign to a secondary server
library;

export 'src/at_auth.dart';
// The options AtAuth.create takes: the at_auth scheme, the two
// authenticators, and the retry policy.
export 'src/auth/at_auth_scheme.dart';
export 'src/auth/cram_authenticator.dart';
export 'src/auth/pkam_authenticator.dart';
export 'src/auth/retry_options.dart';
// KeyIds names the structural fields of an .atKeys document and the keyId
// tokens this package writes — needed to look up typed material via AtKeys.getKey.
export 'src/keys/serialization/key_ids.dart';

// Contains method related to submit, approve and deny an enrollment.
export 'src/enroll/at_enrollment.dart';
// How an enrollment's apkamSymmetricKey reaches its approver — an axis
// independent of the at_auth scheme.
export 'src/enroll/apkam_key_conveyance.dart';
// Contains fields related to enrollment response received from the secondary server
export 'src/enroll/models/at_enrollment_response.dart';
// Contains the NamespacePermission model
export 'src/enroll/models/namespace_permission.dart';
// Contains the Otp model
export 'src/enroll/models/otp.dart';

/// The class stores enrollment request details. It notifies the approving app upon receiving a
/// request from the requesting app, for approval or denial.
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
