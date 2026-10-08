import 'secondary_address_finder.dart';

/// Resolves every atSign to one fixed address.
///
/// The atDirectory lookup is a line protocol over raw TLS, which a browser
/// cannot open — so a web client reaches its atServer through a reverse proxy
/// that has already done the lookup. This is that arrangement as a type: give
/// it the proxy's host and port and it answers without touching the network,
/// which takes `dart:io` off the address path. The transport is still the
/// caller's to supply.
///
/// It is the directly-constructed form of the `proxy:` convention
/// `CacheableSecondaryAddressFinder` honours, where a rootDomain of
/// `proxy:<host>` and a rootPort carry the same two values through a string.
/// Both remain; only this one is reachable without `dart:io`.
class ProxySecondaryAddressFinder implements SecondaryAddressFinder {
  final SecondaryAddress _address;

  ProxySecondaryAddressFinder(String host, int port)
      : _address = SecondaryAddress(host, port);

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      _address;
}
