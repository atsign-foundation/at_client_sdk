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
    Map<String, dynamic> clientConfig = const {},
  }) =>
      secureSocketLookUps(onConnect: (connection) async {
        await connection.sendSync('from:$atSign\n');
      })(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        secondaryAddressFinder: secondaryAddressFinder,
        clientConfig: clientConfig,
      );
}
