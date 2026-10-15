import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup_web.dart';

/// Sends `from:<atSign>` on [connection] before anything else, which tells a
/// proxy fronting many atServers which one the connection is for.
Future<void> Function(AtCommandExecutor connection) proxyPreamble(
        String atSign) =>
    (connection) async {
      await connection.sendSync('from:$atSign\n');
    };

/// [webSocketLookUps] to the proxy at `wss://host:port` + [path], every
/// connection opening with [proxyPreamble] for the atSign it is made for.
AtLookUpFactory proxyWebSocketLookUps({
  required String host,
  required int port,
  String path = '/ws',
}) =>
    ({
      required String atSign,
      required AtRootDomain rootDomain,
      required AtAuthenticator? authenticator,
      SecondaryAddressFinder? secondaryAddressFinder,
      Map<String, dynamic> clientConfig = const {},
    }) =>
        webSocketLookUps(
          host: host,
          port: port,
          path: path,
          onConnect: proxyPreamble(atSign),
        )(
          atSign: atSign,
          rootDomain: rootDomain,
          authenticator: authenticator,
          secondaryAddressFinder: secondaryAddressFinder,
          clientConfig: clientConfig,
        );
