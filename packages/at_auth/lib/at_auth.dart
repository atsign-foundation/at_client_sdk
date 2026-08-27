/// The [AtAuth] package contains common logic for onboarding/authenticating an atSign to a secondary server
library;

export 'src/at_auth.dart';
export 'src/auth_constants.dart';
// Builds the AtAuthenticator at_lookup takes, over this package's keystore.
// at_lookup cannot name AtKeys or AtKeysIo, so the credential, the enrollment
// and the signing algorithm all stay on this side of that seam.
export 'src/auth/at_authenticator.dart';
// Reachability probes. `httpsProbe` is WASM-safe; `defaultProbe` is
// whichever of it and `secureSocketProbe` suits the platform compiled for.
export 'src/auth/probe_default.dart';
export 'src/auth/server_probe.dart';

// Contains models related to onboarding and authentication requests and responses.
export 'src/auth/models/at_auth_requests.dart';
export 'src/auth/models/at_auth_responses.dart';
export 'src/auth/models/at_auth_session.dart';
// Contains method related to submit, approve and deny an enrollment.
export 'src/enroll/at_enrollment.dart';
// How a retrofit's read-decide-write sequence is serialised against other
// processes. Left unset it runs directly; a caller whose keys are on disk
// assigns fileRetrofitSerializer from at_auth_io.dart.
export 'src/enroll/retrofit_serializer.dart';
// Composes the `_apsk` signing-key advertisement an enrollment publishes.
export 'src/enroll/apsk_advertisement.dart';
// The proof of possession an enroll:update carries when it installs a new
// APKAM public key. A cross-tier contract with every atServer implementation.
export 'src/enroll/apkam_possession_proof.dart';
// What an approved enrollment is asking to change about its own record.
export 'src/enroll/models/enrollment_update_request.dart';
// The status every advertised key entry in the protocol carries: an open
// token whose two known values are active and retired.
export 'src/enroll/key_entry_status.dart';
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
export 'src/keys/at_keys.dart';
// CryptographicMaterial is the API-level typed key material — the only type
// AtKeys's API deals in. It owns its own JSON (de)serialization; the
// document-level `keys[]` grouping/validation lives in
// parseAtKeysDocument/encodeAtKeysDocument, also exported here.
export 'src/keys/serialization/atkey_material.dart';
export 'src/keys/serialization/assurance.dart';
export 'src/keys/serialization/passphrase_envelope.dart';
export 'src/keys/io/at_keys_io.dart';
// FileAtKeysIo is NOT here: it needs dart:io, which dart2wasm refuses
// anywhere reachable from this barrel. It lives in at_auth_io.dart.
export 'src/keys/io/memory_io.dart';

/// Classes for registrar services
export 'src/registrar/registrar.dart';
export 'src/registrar/registrar_service.dart';
