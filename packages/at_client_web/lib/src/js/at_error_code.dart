import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart' show JsCollectionsError;
import '../session/portal_session.dart';
import 'js_session.dart';

/// The codes [atErrorCode] returns for a failure that is not a
/// `COLLECTION_*` one: the closed set, sorted.
///
/// `tool/manifest.dart` publishes this list as `errorCodes`, beside the
/// collection codes and the exported surface, in `bridge-manifest.json`.
const atErrorCodes = <String>[
  'bad_key',
  'closed',
  'enrollment_conveyance_failed',
  'enrollment_denied',
  'internal',
  'offline',
  'onboarding_incomplete',
  'pkam_refused',
  'unsupported',
];

/// The `AtError.code` for [error]: one string per typed exception the
/// session layer throws, a `COLLECTION_*` code for a collection failure, and
/// `internal` for anything else.
String atErrorCode(Object error) => switch (error) {
      JsCollectionsError(:final code) => code,
      AtOpenRefusedException() => 'pkam_refused',
      PortalSessionOfflineException() => 'offline',
      AtEnrollmentPendingException() => 'onboarding_incomplete',
      EnrollmentConveyanceException() => 'enrollment_conveyance_failed',
      AtEnrollmentException() => 'enrollment_denied',
      SessionClosedException() || StoppedException() => 'closed',
      UnsupportedKeyMaterialException() ||
      UnsupportedError() ||
      ManageAccessException() =>
        'unsupported',
      BadKeyException() ||
      AtNoCredentialException() ||
      InvalidAtSignException() =>
        'bad_key',
      _ => 'internal',
    };
