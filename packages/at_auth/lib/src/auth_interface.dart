import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

import 'auth/cram_authenticator.dart';

/// This abstract class defines the interface for authentication and enrollment
/// with an @protocol server.
abstract class AtAuthInterface {
  /// Retrieves an instance of [AtEnrollmentBase] for the provided [atSign].
  /// This method facilitates the enrollment process.
  ///
  /// - [atSign]: The @sign for which enrollment is requested.
  ///
  /// Returns an instance of [AtEnrollmentBase].
  AtEnrollmentBase atEnrollment(String atSign);

  /// Retrieves an instance of [AtAuth].
  /// This method facilitates the authentication process.
  ///
  /// Returns an instance of [AtAuth].
  AtAuth atAuth(
      {AtLookUp? atLookUp,
      AtChops? atChops,
      CramAuthenticator? cramAuthenticator,
      PkamAuthenticator? pkamAuthenticator,
      AtEnrollmentBase? atEnrollmentBase});
}
