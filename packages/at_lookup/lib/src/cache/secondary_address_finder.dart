abstract class SecondaryAddressFinder {
  Future<SecondaryAddress> findSecondary(String atSign);
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
