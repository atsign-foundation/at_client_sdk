import 'package:at_lookup/at_lookup_web.dart';

import 'dev_session_options.dart';
import 'portal_session.dart';
import 'proxy_lookups.dart';

/// The transport a browser session uses for [options].
///
/// With no `proxy`, each atSign's own atServer is reached over its `/ws`,
/// found through the root's HTTPS lookup. With one, every connection goes to
/// it and every atSign resolves to it. There is no fallback from one to the
/// other.
SessionTransport sessionTransport(DevSessionOptions options) {
  final root = options.root;
  return switch (options.proxy) {
    null => (
        lookUps: webSocketLookUps(directoryPort: root.rootPort),
        finder:
            HttpsSecondaryAddressFinder(root.rootDomain, port: root.rootPort),
      ),
    (:final host, :final port) => (
        lookUps: proxyWebSocketLookUps(host: host, port: port),
        finder: FixedSecondaryAddressFinder(host, port),
      ),
  };
}
