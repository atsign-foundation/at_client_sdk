import 'package:at_commons/at_commons.dart' show IllegalArgumentException;

class AtRootDomain {
  final String rootDomain;
  final int rootPort;

  const AtRootDomain(this.rootDomain, this.rootPort);

  static int _parseRootPort(String value) {
    try {
      var port = int.parse(value);
      if (port < 1 || port > 65535) {
        throw IllegalArgumentException("$value is not a valid port number");
      }
      return port;
    } catch (_) {
      throw IllegalArgumentException(
        "$value is not a valid integer for root port",
      );
    }
  }

  factory AtRootDomain.parse(String value) {
    if (value.isEmpty) {
      throw IllegalArgumentException("Invalid root: value to parse is empty");
    }
    var parts = value.split(":");
    switch (parts.length) {
      case 1:
        return AtRootDomain(value, 64);
      case 2:
        if (parts[0] == "proxy") {
          return AtRootDomain(value, 64);
        }
        return AtRootDomain(parts[0], _parseRootPort(parts[1]));
      case 3:
        if (parts[0] != "proxy") {
          throw IllegalArgumentException(
            "Got three parts for root, expected proxy as the first but got: ${parts[0]}",
          );
        }
        return AtRootDomain(
          "${parts[0]}:${parts[1]}",
          _parseRootPort(parts[2]),
        );
      default:
        throw IllegalArgumentException("Invalid root domain: $value");
    }
  }

  bool get isProxyAddress => rootDomain.startsWith("proxy:");
}
