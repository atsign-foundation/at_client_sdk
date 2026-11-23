import 'package:at_client/at_client.dart';

import '../collections/js_collections_adapter.dart' show JsCollectionsError;
import '../session/portal_session.dart';
import 'js_session.dart';

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
