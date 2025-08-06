import 'package:at_auth/at_auth.dart';
import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/auth_interface.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

import 'enroll/at_enrollment_impl.dart';

class AtAuthInterfaceImpl implements AtAuthInterface {
  @override
  AtEnrollmentBase atEnrollment(String atSign) {
    return AtEnrollmentImpl(atSign);
  }

  @override
  AtAuth atAuth(
      {AtLookUp? atLookUp,
      AtChops? atChops,
      CramAuthenticator? cramAuthenticator,
      PkamAuthenticator? pkamAuthenticator,
      AtEnrollmentBase? atEnrollmentBase}) {
    return AtAuthImpl(
        atLookUp: atLookUp,
        atChops: atChops,
        cramAuthenticator: cramAuthenticator,
        pkamAuthenticator: pkamAuthenticator,
        atEnrollmentBase: atEnrollmentBase);
  }
}
