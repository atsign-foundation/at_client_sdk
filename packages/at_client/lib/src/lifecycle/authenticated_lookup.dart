import 'package:at_auth/at_auth.dart' show AtKeysIo, authenticatorFor;
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, SecureSocketConfig, UnAuthenticatedException;
import 'package:at_lookup/at_lookup_io.dart';

/// A connection to [atSign]'s atServer authenticated as [enrollmentId], or
/// as the enrollment [keys] name when none is given; the caller closes it.
///
/// With [on], that connection is authenticated and handed back instead of a
/// new one, and stays open whatever the answer. A refusal throws
/// [UnAuthenticatedException], or whatever the handshake threw, and a
/// connection built here is closed first.
Future<AtLookUp> authenticatedLookUp(
  String atSign,
  AtKeysIo keys,
  AtRootDomain rootDomain, {
  String? enrollmentId,
  AtLookUp? on,
}) async {
  final id =
      enrollmentId ?? (await keys.read(atSign)).enrollmentToAuthenticateAs();
  final lookUp = on ??
      AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          transport: secureSocketTransport(SecureSocketConfig()),
          authenticator: authenticatorFor(keys, atSign, enrollmentId: id));
  try {
    if (!await lookUp.pkamAuthenticate(enrollmentId: id)) {
      throw UnAuthenticatedException('$atSign could not authenticate as '
          '$id: the atServer refused the PKAM');
    }
  } catch (_) {
    if (on == null) await lookUp.close();
    rethrow;
  }
  return lookUp;
}
