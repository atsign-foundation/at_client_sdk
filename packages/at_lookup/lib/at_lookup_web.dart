/// at_lookup on a browser WebSocket: everything in `at_lookup.dart`, plus the
/// transport that reaches an atServer over WebSockets in a browser.
///
/// The split exists so that naming the browser transport is what pulls the
/// web imports in. A caller that imports only `at_lookup.dart` and injects
/// its own transport does not acquire `package:web` through a default it never
/// asked for.
///
/// A browser cannot open raw TLS, so the atDirectory lookup has no web half:
/// a caller reaches its atServer through a proxy it names, which is what
/// [webSocketLookUps] takes.
library;

import 'package:at_commons/at_commons.dart' show AtRootDomain;

import 'at_lookup.dart';

import 'src/web/web_socket_transport.dart' show WebSocketTransportFactory;

export 'at_lookup.dart';
export 'src/web/web_socket_transport.dart';

/// A browser WebSocket — the transport to pass to `AtLookUp.withTransport`
/// unless you are supplying your own. [scheme] is `ws` only for tests.
AtLookupTransportFactories webSocketTransport(
        {String path = '/ws', String scheme = 'wss'}) =>
    AtLookupTransportFactories(
        transportFactory:
            WebSocketTransportFactory(path: path, scheme: scheme));

/// An [AtLookUpFactory] with every connection a WebSocket to
/// `wss://host:port` + [path], through `AtLookUp.withTransport`.
///
/// Every atSign resolves to [host]:[port] unless the factory is called with
/// its own `secondaryAddressFinder`. [onConnect] runs on each connection
/// before anything else is sent on it: the proxy's `from:` goes there.
AtLookUpFactory webSocketLookUps({
  required String host,
  required int port,
  String path = '/ws',
  Future<void> Function(AtCommandExecutor connection)? onConnect,
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
        secondaryAddressFinder:
            secondaryAddressFinder ?? ProxySecondaryAddressFinder(host, port),
        clientConfig: clientConfig,
        onConnect: onConnect,
      );
}
