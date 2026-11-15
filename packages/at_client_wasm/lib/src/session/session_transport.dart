import 'package:at_lookup/at_lookup_web.dart';

import 'portal_session.dart';
import 'session_transport_options.dart';

/// The transport a browser session uses for [options].
///
/// With no `proxy`, each atSign's own atServer is reached over its `/ws`,
/// found through the root's HTTPS lookup. With one, every connection goes to
/// it and every atSign resolves to it, and at_lookup sends `from:<atSign>`
/// first on each connection because the root is `proxy:<host>`. There is no
/// fallback from one to the other. Either way the transport carries
/// [options]' root.
SessionTransport sessionTransport(SessionTransportOptions options) {
  final root = options.root;
  return switch (options.proxy) {
    null => (
        lookUps: webSocketLookUps(directoryPort: root.rootPort),
        finder:
            HttpsSecondaryAddressFinder(root.rootDomain, port: root.rootPort),
        root: root,
      ),
    (:final host, :final port) => (
        lookUps: fixedAddressWebSocketLookUps(host: host, port: port),
        finder: FixedSecondaryAddressFinder(host, port),
        root: root,
      ),
  };
}
