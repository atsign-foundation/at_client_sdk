/// The registrar admin surface: [RegistrarAdminService], the super-API-key
/// path for registering and deleting Atsigns, and the exceptions it throws.
///
/// An Atsign-specific service sits behind a library of its own, not
/// `at_auth.dart`'s core barrel (architecture invariant A3). It is
/// platform-neutral, same as the rest of `at_auth`; import it alongside
/// `at_auth.dart` wherever the admin API is needed:
///
/// ```dart
/// import 'package:at_auth/at_auth.dart';
/// import 'package:at_auth/at_registrar.dart';
/// ```
library;

export 'src/registrar/registrar_admin_service.dart';
export 'src/registrar/registrar_exceptions.dart';
