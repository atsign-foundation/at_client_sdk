/// at_lookup on a browser WebSocket: everything in `at_lookup.dart`, plus the
/// transport and the atDirectory lookup that reach an atServer from a browser.
///
/// The split exists so that naming the browser transport is what pulls the
/// web imports in. A caller that imports only `at_lookup.dart` and injects
/// its own transport does not acquire `package:web` through a default it never
/// asked for.
///
/// A browser cannot open raw TLS, so [webSocketLookUps] asks the atDirectory
/// over HTTPS and opens `wss://` straight to the atServer, which upgrades
/// `/ws` on its own TLS port. [proxyWebSocketLookUps] sends every atSign
/// through one proxy instead, for development.
library;

import 'package:at_commons/at_commons.dart' show AtRootDomain;

import 'at_lookup.dart';

import 'src/web/https_secondary_address_finder.dart';
import 'src/web/web_socket_transport_factory.dart'
    show WebSocketTransportFactory;

export 'at_lookup.dart';
export 'src/web/https_secondary_address_finder.dart';
export 'src/web/web_socket_transport.dart' show WebSocketTransport;
export 'src/web/web_socket_transport_factory.dart'
    show WebSocketTransportFactory;

/// A browser WebSocket — the transport to pass to `AtLookUp.withTransport`
/// unless you are supplying your own. [scheme] is `ws` only for tests.
AtLookupTransport webSocketTransport(
        {String path = '/ws', String scheme = 'wss'}) =>
    AtLookupTransport(
        transportFactory:
            WebSocketTransportFactory(path: path, scheme: scheme));

/// The browser [AtLookUpFactory]: each atSign is looked up with an
/// [HttpsSecondaryAddressFinder] on the root domain's host at
/// [directoryPort], and each connection is a WebSocket to
/// `wss://atServerHost:port` + [path].
///
/// A factory call's own `secondaryAddressFinder` replaces the lookup.
/// [onConnect] runs on each connection before anything else is sent on it.
///
/// The atDirectory must answer the page's origin with CORS headers for the
/// lookup to succeed.
AtLookUpFactory webSocketLookUps({
  String path = '/ws',
  int directoryPort = 443,
  Future<void> Function(AtCommandExecutor connection)? onConnect,
}) =>
    _webSocketLookUps(
        path: path,
        finderFor: (rootDomain) => HttpsSecondaryAddressFinder(
            rootDomain.rootDomain,
            port: directoryPort),
        onConnectFor: (_) => onConnect);

/// An [AtLookUpFactory] for development, with every atSign resolving to the
/// proxy at `wss://host:port` + [path].
///
/// Each connection opens with [proxyPreamble] for its atSign, which tells
/// the proxy which atServer to reach, unless [onConnect] is given to run
/// instead. The proxy ends TLS and so sees the session in the clear.
AtLookUpFactory proxyWebSocketLookUps({
  required String host,
  required int port,
  String path = '/ws',
  Future<void> Function(AtCommandExecutor connection)? onConnect,
}) =>
    _webSocketLookUps(
        path: path,
        finderFor: (_) => ProxySecondaryAddressFinder(host, port),
        onConnectFor: (atSign) => onConnect ?? proxyPreamble(atSign));

/// Sends `from:<atSign>` on a connection, which tells a proxy fronting many
/// atServers which one the connection is for.
Future<void> Function(AtCommandExecutor connection) proxyPreamble(
        String atSign) =>
    (connection) async {
      await connection.sendSync('from:$atSign\n');
    };

AtLookUpFactory _webSocketLookUps({
  required String path,
  required SecondaryAddressFinder Function(AtRootDomain rootDomain) finderFor,
  required Future<void> Function(AtCommandExecutor connection)? Function(
          String atSign)
      onConnectFor,
}) {
  final transport = webSocketTransport(path: path);
  return ({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
    Map<String, dynamic> clientConfig = const {},
  }) =>
      AtLookUp.withTransport(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        transport: transport,
        secondaryAddressFinder: secondaryAddressFinder ?? finderFor(rootDomain),
        clientConfig: clientConfig,
        onConnect: onConnectFor(atSign),
      );
}
