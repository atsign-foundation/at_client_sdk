abstract class SecondaryAddressFinder {
  /// Finds the atServer address for [atSign] by looking it up in the atDirectory.
  ///
  /// [timeout] bounds the TOTAL wall-clock spent doing so (connect + the
  /// internal retries + waiting for the atDirectory response). When null, the
  /// process-wide default (`AtNetworkTimeouts.effectiveDefault`, 30s) is used,
  /// and the value is always capped at `AtNetworkTimeouts.maxAllowed` (60s). On
  /// expiry the socket is closed and an `AtTimeoutException` is thrown.
  Future<SecondaryAddress> findSecondary(String atSign, {Duration? timeout});
}

class SecondaryAddress {
  final String host;
  final int port;
  SecondaryAddress(this.host, this.port);

  @override
  String toString() {
    return '$host:$port';
  }
}
