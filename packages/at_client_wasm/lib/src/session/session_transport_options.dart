import 'package:at_client/at_client.dart';

const _proxyPrefix = 'proxy:';

/// How a browser session reaches atServers: directly, through an
/// atDirectory, or through one proxy for every connection.
class SessionTransportOptions {
  /// The root every connection of the session is built for: the atDirectory
  /// Atsigns are looked up at, by default the production one, or
  /// `proxy:<host>` at the proxy's port.
  final AtRootDomain root;

  /// Throws an [ArgumentError] naming the field for a [proxyHost] without a
  /// [proxyPort] or the reverse, an empty [proxyHost], a [proxyPort] outside
  /// 1-65535, a [root] given with a proxy, and a `proxy:` [root] with an
  /// empty host or a port outside 1-65535.
  SessionTransportOptions(
      {AtRootDomain? root, String? proxyHost, int? proxyPort})
      : root = _root(root, proxyHost, proxyPort);

  /// The proxy every connection goes through, or null for direct: each
  /// Atsign's own atServer is reached over its `/ws`, found through [root]'s
  /// HTTPS lookup.
  ({String host, int port})? get proxy => root.isProxyAddress
      ? (
          host: root.rootDomain.substring(_proxyPrefix.length),
          port: root.rootPort
        )
      : null;

  static AtRootDomain _root(AtRootDomain? root, String? host, int? port) {
    final proxy = _proxy(host, port);
    if (proxy != null) {
      if (root != null) {
        throw ArgumentError.value(
            root.rootDomain, 'root', 'cannot be given with a proxy');
      }
      return AtRootDomain('$_proxyPrefix${proxy.host}', proxy.port);
    }
    if (root == null) return AtRootDomain.atsignDomain;
    if (root.isProxyAddress) {
      if (root.rootDomain.substring(_proxyPrefix.length).trim().isEmpty) {
        throw ArgumentError.value(
            root.rootDomain, 'root', 'names no proxy host');
      }
      _checkPort(root.rootPort, 'root');
    }
    return root;
  }

  static ({String host, int port})? _proxy(String? host, int? port) {
    if (host == null) {
      if (port == null) return null;
      throw ArgumentError.value(port, 'proxyPort', 'needs a proxyHost');
    }
    if (host.trim().isEmpty) {
      throw ArgumentError.value(host, 'proxyHost', 'must not be empty');
    }
    if (port == null) {
      throw ArgumentError.value(
          null, 'proxyPort', 'is required with a proxyHost');
    }
    _checkPort(port, 'proxyPort');
    return (host: host, port: port);
  }

  static void _checkPort(int port, String name) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, name, 'must be 1-65535');
    }
  }
}
