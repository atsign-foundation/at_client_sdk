///class to store configuration to create a security context while creating secure sockets
class SecureSocketConfig {
  ///setting to true will create a Secure Socket with Security Context. setting to false will just create a Secure Socket
  ///setting to true will save session TLS keys at the provided path in [tlsKeysSavePath]
  bool decryptPackets = false;

  ///creating a Security Context requires providing a certificate. [pathToCerts] will be the path to this certificate.
  String? pathToCerts;

  ///location of where the TLS keys file will be stored.
  String? tlsKeysSavePath;

  /// Maximum time to wait for the TCP + TLS connect to complete. When null,
  /// [AtNetworkTimeouts.effectiveDefault] is used. The resolved value is always
  /// capped at [AtNetworkTimeouts.maxAllowed].
  Duration? connectTimeout;
}
