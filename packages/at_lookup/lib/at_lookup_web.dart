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
/// `/ws` on its own TLS port. [fixedAddressWebSocketLookUps] skips the
/// atDirectory and connects every atSign to one atServer, for development.
///
/// [tabSharedLookUps] wraps either so that the tabs of one origin share one
/// monitor connection, the one notifications arrive on, while each keeps a
/// connection of its own for its requests.
library;

import 'package:at_commons/at_commons.dart' show AtRootDomain;

import 'at_lookup.dart';

import 'src/web/browser_shared_monitor_ports.dart';
import 'src/web/https_secondary_address_finder.dart';
import 'src/web/web_socket_transport_factory.dart'
    show WebSocketTransportFactory;

export 'at_lookup.dart';
export 'src/web/browser_shared_monitor_ports.dart';
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
        onConnect: onConnect);

/// An [AtLookUpFactory] for development, connecting every atSign to the
/// atServer at `wss://host:port` + [path] without asking the atDirectory.
///
/// [onConnect] runs on each connection before anything else is sent on it.
AtLookUpFactory fixedAddressWebSocketLookUps({
  required String host,
  required int port,
  String path = '/ws',
  Future<void> Function(AtCommandExecutor connection)? onConnect,
}) =>
    _webSocketLookUps(
        path: path,
        finderFor: (_) => FixedSecondaryAddressFinder(host, port),
        onConnect: onConnect);

/// An [AtLookUpFactory] whose muxables share one monitor connection across
/// the browser's tabs: one tab holds the Web Lock
/// `at-monitor:<atSign>:<scope>`, runs notifications on the muxable [inner]
/// builds for it and relays them on a `BroadcastChannel` of the same name;
/// the other tabs listen. The lock passes when the holder closes, and is
/// taken from a holder the browser has frozen when [steal] is true.
///
/// For `buildAtClient`'s `notificationLookUps`; the client's own requests
/// keep going through [inner]. [scope] separates the clients of one atSign
/// that must not share: pass the enrollment id the client runs as, or
/// `'primary'`. The tabs that are to share must pass the same value.
///
/// [beaconInterval] is how often the leading tab says it is alive; a tab
/// that misses three beacons and gets no answer to a hello steals the lock
/// one interval later. [staleAfter] is how long the leader's connection may
/// be silent before the page coming back into view makes it reconnect.
AtLookUpFactory tabSharedLookUps(
  AtLookUpFactory inner, {
  required String scope,
  Duration beaconInterval = const Duration(seconds: 30),
  Duration staleAfter = const Duration(seconds: 60),
  bool steal = true,
}) =>
    sharedMonitorLookUps(
      inner,
      lock: const BrowserMonitorLock(),
      channels: BrowserMonitorChannel.new,
      lifecycle: BrowserPageLifecycle(),
      scope: scope,
      beaconInterval: beaconInterval,
      staleAfter: staleAfter,
      steal: steal,
    );

AtLookUpFactory _webSocketLookUps({
  required String path,
  required SecondaryAddressFinder Function(AtRootDomain rootDomain) finderFor,
  required Future<void> Function(AtCommandExecutor connection)? onConnect,
}) {
  final transport = webSocketTransport(path: path);
  return ({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    SecondaryAddressFinder? secondaryAddressFinder,
  }) =>
      AtLookUp.withTransport(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        transport: transport,
        secondaryAddressFinder: secondaryAddressFinder ?? finderFor(rootDomain),
        onConnect: onConnect,
      );
}
