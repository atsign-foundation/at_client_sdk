import 'package:at_client/at_client.dart';

import 'portal_session.dart';

/// What a dev session needs to open besides its keys.
class DevSessionOptions {
  /// The session's atSign, normalized to `@name` form.
  final String atSign;
  final String app;

  /// The dev proxy every connection goes through, or null for direct: each
  /// atSign's own atServer is reached over its `/ws`, found through [root]'s
  /// HTTPS lookup.
  final ({String host, int port})? proxy;

  /// The root server (atDirectory) atSigns are looked up at.
  final AtRootDomain root;

  /// Throws an [ArgumentError] naming the field for a [proxyHost] without a
  /// [proxyPort] or the reverse, an empty [proxyHost] and a [proxyPort]
  /// below 1.
  DevSessionOptions({
    required String atSign,
    required this.app,
    String? proxyHost,
    int? proxyPort,
    this.root = AtRootDomain.atsignDomain,
  })  : atSign = normalizeAtSign(atSign),
        proxy = _proxy(proxyHost, proxyPort);

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
    if (port < 1) {
      throw ArgumentError.value(port, 'proxyPort', 'must be positive');
    }
    return (host: host, port: port);
  }
}
