class RootServerInfo {
  final String host;
  final int port;
  final bool isUsingProxy;

  RootServerInfo({
    required this.host,
    required this.port,
    this.isUsingProxy = false,
  });
}

class RootServerParser {
  static const int defaultPort = 64;
  static const String defaultHost = 'root.atsign.org';

  static RootServerInfo parse(String rawRootServer) {
    bool isUsingProxy = false;
    String host = defaultHost;
    int port = defaultPort;

    if (rawRootServer.startsWith('proxy:')) {
      // Handle proxy:host:port or proxy:host format
      isUsingProxy = true;
      String serverPart = rawRootServer.substring(6); // Remove 'proxy:' prefix

      if (serverPart.contains(':')) {
        // proxy:host:port format
        List<String> parts = serverPart.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? defaultPort;
      } else {
        // proxy:host format
        host = serverPart;
        port = defaultPort;
      }
    } else if (rawRootServer.contains(':')) {
      // Handle host:port format
      List<String> parts = rawRootServer.split(':');
      host = parts[0];
      port = int.tryParse(parts[1]) ?? defaultPort;
      isUsingProxy = false;
    } else {
      // Handle host format
      host = rawRootServer;
      port = defaultPort;
      isUsingProxy = false;
    }

    return RootServerInfo(
      host: host,
      port: port,
      isUsingProxy: isUsingProxy,
    );
  }
}