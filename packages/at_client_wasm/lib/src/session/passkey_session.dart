import 'package:at_client/at_client.dart';

import 'enrollment_gateway.dart';
import 'passkey_custody.dart';
import 'portal_session.dart';
import 'session_open.dart';

/// Onboards [atSign] through [custody] with [cram] and returns a client on
/// the keys it holds, PKAM'd before return.
///
/// A failure after the atSign is activated closes the custody session.
Future<AtClient> onboardSession(PasskeyCustody custody,
        {required String atSign,
        required String cram,
        required String app,
        required SessionTransport transport,
        AtRootDomain root = AtRootDomain.atsignDomain}) async =>
    _clientOn(await custody.onboard(atSign: atSign, cram: cram),
        app: app, transport: transport, root: root);

/// Opens [atSign]'s @keys through [custody] and returns a client on them,
/// PKAM'd before return.
///
/// Throws [PasskeyLostException] for a passkey that cannot open [atSign]
/// (no credential, no pointer, PKAM refused), [MissingAtKeysDocumentException]
/// or [PublicKeyMismatchException]; none leaves a session open.
Future<AtClient> loginSession(PasskeyCustody custody,
        {required String atSign,
        required String app,
        required SessionTransport transport,
        AtRootDomain root = AtRootDomain.atsignDomain}) async =>
    _clientOn(await custody.open(atSign: atSign),
        app: app, transport: transport, root: root);

/// A client on [custody]'s restored @keys plus the APKAM key its seed derives,
/// opened without [portalSession]'s refusal of ML-DSA-65 material: these keys
/// came from the passkey-held document, not from a caller.
///
/// [custody] is closed exactly once, after the client has its own connection
/// or the open failed; a failed open rethrows its own error. If the open
/// succeeded and the close throws, the client is stopped (a failed stop is
/// logged) and the close error is rethrown.
Future<AtClient> _clientOn(CustodySession custody,
    {required String app,
    required SessionTransport transport,
    required AtRootDomain root}) async {
  final AtClient client;
  try {
    final pair = await apkamKeyPairFromSeed(custody.authSeed);
    final keys = withApkamKey(
        AtKeys.fromJson(custody.atKeys), custody.enrollmentId, pair);
    client = await openSession(
        atSign: custody.atSign,
        app: app,
        keys: keys,
        transport: transport,
        root: root);
  } catch (_) {
    await custody.close();
    rethrow;
  }
  try {
    await custody.close();
  } catch (_) {
    await stopQuietly(client, custody.atSign);
    rethrow;
  }
  return client;
}
