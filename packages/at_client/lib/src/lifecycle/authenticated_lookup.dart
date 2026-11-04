import 'package:at_auth/at_auth.dart' show AtKeysIo, authenticatorFor;
import 'package:at_commons/at_commons.dart'
    show AtRootDomain, UnAuthenticatedException;
import 'package:at_lookup/at_lookup.dart'
    show AtLookUp, AtLookUpFactory, SecondaryAddressFinder;

/// A connection to [atSign]'s atServer authenticated as [enrollmentId], or
/// as the enrollment [keys] name when none is given; the caller closes it.
///
/// [lookUps] builds the connection, which finds the atServer through
/// [secondaryAddressFinder]. A refusal throws
/// [UnAuthenticatedException], or whatever the handshake threw, and the
/// connection is closed first.
Future<AtLookUp> authenticatedLookUp(
  String atSign,
  AtKeysIo keys,
  AtRootDomain rootDomain, {
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
  String? enrollmentId,
}) async {
  final id =
      enrollmentId ?? (await keys.read(atSign)).enrollmentToAuthenticateAs();
  final lookUp = lookUps(
      atSign: atSign,
      rootDomain: rootDomain,
      authenticator: authenticatorFor(keys, atSign, enrollmentId: id),
      secondaryAddressFinder: secondaryAddressFinder);
  try {
    if (!await lookUp.pkamAuthenticate()) {
      throw UnAuthenticatedException('$atSign could not authenticate as '
          '$id: the atServer refused the PKAM');
    }
  } catch (_) {
    await lookUp.close();
    rethrow;
  }
  return lookUp;
}
