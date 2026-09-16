import 'package:at_auth/at_auth.dart' show AtKeysIo, authenticatorFor;
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, UnAuthenticatedException;
import 'package:at_lookup/at_lookup.dart' show AtLookUp, AtLookUpFactory;

/// A connection to [atSign]'s atServer authenticated as [enrollmentId], or
/// as the enrollment [keys] name when none is given; the caller closes it.
///
/// [lookUps] builds the connection. With [on], that connection is
/// authenticated and handed back instead of a new one, and stays open
/// whatever the answer. A refusal throws
/// [UnAuthenticatedException], or whatever the handshake threw, and a
/// connection built here is closed first.
Future<AtLookUp> authenticatedLookUp(
  String atSign,
  AtKeysIo keys,
  AtRootDomain rootDomain, {
  required AtLookUpFactory lookUps,
  String? enrollmentId,
  AtLookUp? on,
}) async {
  final id =
      enrollmentId ?? (await keys.read(atSign)).enrollmentToAuthenticateAs();
  final lookUp = on ??
      lookUps(
          atSign: atSign,
          rootDomain: rootDomain,
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
