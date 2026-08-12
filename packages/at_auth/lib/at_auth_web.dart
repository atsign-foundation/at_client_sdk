/// The platform-neutral surface of at_auth — onboarding, authentication and
/// APKAM enrollment, with **no `dart:io` type named anywhere**.
///
/// Import this instead of `at_auth.dart` when building for the web (dart2wasm or
/// dart2js). Everything here is also exported from `at_auth.dart`, so this
/// barrel is a *narrowing*, not a different API: code written against it runs
/// unchanged on native.
///
/// What `at_auth.dart` adds and this omits:
///
/// - `FileAtKeysIo` — a browser has no file system. Supply an `AtKeysIo` of your
///   own (`InMemoryAtKeysIo` is exported here) via `AtOnboardingRequest.atKeysIo`.
/// - `secureSocketProbe` — the TLS atServer readiness probe. Without it
///   `validateAtServer` still polls the atDirectory but does not wait for the
///   atServer to start listening.
///
/// Both have platform-conditional defaults inside `AtAuthImpl`, so on native you
/// get them without asking and on web you get neither. Nothing throws at import
/// time; the difference shows up as a missing default, not a crash.
///
/// Note this barrel is not sufficient to *run* at_auth on the web today —
/// `at_lookup`'s socket transport still needs porting. See
/// `docs/projects/wasm/plan.md`.
library;

export 'src/at_auth.dart';
export 'src/auth_constants.dart';

// Contains models related to onboarding and authentication requests and responses.
export 'src/auth/models/at_auth_requests.dart';
export 'src/auth/models/at_auth_responses.dart';
export 'src/auth/models/at_auth_session.dart';
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
export 'src/keys/at_keys.dart';
// AtKeysMaterial is the API-level typed key material — the only type
// AtKeys's API deals in. It owns its own JSON (de)serialization; the
// document-level `keys[]` grouping/validation lives in
// parseAtKeysDocument/encodeAtKeysDocument, also exported here.
export 'src/keys/serialization/atkey_material.dart';
export 'src/keys/serialization/assurance.dart';
export 'src/keys/serialization/passphrase_envelope.dart';
export 'src/keys/io/at_keys_io.dart';
// FileAtKeysIo is `dart:io`-only: see package:at_auth/at_auth.dart
export 'src/keys/io/memory_io.dart';

/// Classes for registrar services
export 'src/registrar/registrar.dart';
export 'src/registrar/registrar_service.dart';
