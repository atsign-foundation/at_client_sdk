import 'package:at_auth/at_auth.dart' show AtEnrollmentResponse;
import 'package:at_client/at_client_io.dart';
// ignore: implementation_imports
import 'package:at_client/src/preference/client_config.dart' show enrollmentFor;

/// Waits for [response]'s enrollment to be approved, over a connection to
/// [atSign]'s atServer opened for the wait and closed when it ends, whose
/// `from:` carries the clientConfig at_client sends.
Future<void> awaitEnrollmentApproval(AtEnrollmentResponse response,
    {required String atSign, required AtRootDomain rootDomain}) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: rootDomain, authenticator: null);
  try {
    await enrollmentFor(null).waitForApproval(response, atLookup: lookUp);
  } finally {
    await lookUp.close();
  }
}
