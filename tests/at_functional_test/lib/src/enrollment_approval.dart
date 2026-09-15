import 'package:at_auth/at_auth.dart' show AtEnrollment, AtEnrollmentResponse;
import 'package:at_client/at_client.dart';

/// Waits for [response]'s enrollment to be approved, over a connection to
/// [atSign]'s atServer opened for the wait and closed when it ends.
Future<void> awaitEnrollmentApproval(AtEnrollmentResponse response,
    {required String atSign, required AtRootDomain rootDomain}) async {
  final lookUp = secureSocketLookUps()(
      atSign: atSign, rootDomain: rootDomain, authenticator: null);
  try {
    await AtEnrollment.create().waitForApproval(response, atLookup: lookUp);
  } finally {
    await lookUp.close();
  }
}
