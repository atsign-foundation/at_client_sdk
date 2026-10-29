import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup_io.dart';

/// Connections through a proxy that fronts many atServers: the proxy learns
/// which one this connection is for from a `from:<atSign>` sent before
/// anything else, on every connection, so that is what each one does first.
/// TLS on TCP underneath, as the default factory.
AtLookUpFactory proxyLookUps() {
  return ({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) =>
      secureSocketLookUps(onConnect: (connection) async {
        await connection.sendSync('from:$atSign\n');
      })(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        secondaryAddressFinder: secondaryAddressFinder,
      );
}

/// The `lookUps` for a client whose atDirectory is [rootDomain]:
/// [proxyLookUps] when it names a proxy (`proxy:<host>`), and
/// [secureSocketLookUps] otherwise.
AtLookUpFactory lookUpsFor(String rootDomain) =>
    rootDomain.startsWith('proxy:') ? proxyLookUps() : secureSocketLookUps();
