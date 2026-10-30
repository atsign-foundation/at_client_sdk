import 'secondary_address_finder.dart';

/// Resolves every atSign to one fixed address, without touching the network.
///
/// For an atServer whose address is already known, such as a local virtual
/// environment's, and reachable without `dart:io`. It is the
/// directly-constructed form of the `proxy:` convention
/// `CacheableSecondaryAddressFinder` honours, where a rootDomain of
/// `proxy:<host>` and a rootPort carry the same two values through a string.
class FixedSecondaryAddressFinder implements SecondaryAddressFinder {
  final SecondaryAddress _address;

  FixedSecondaryAddressFinder(String host, int port)
      : _address = SecondaryAddress(host, port);

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      _address;
}
