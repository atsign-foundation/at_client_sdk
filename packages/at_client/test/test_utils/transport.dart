import 'dart:io';

import 'package:at_client/at_client_io.dart';

/// The hosts a unit test's atDirectory may be on.
const Set<String> loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// The atDirectory [preference] names, asked over TLS: what a native program
/// passes as a client's `secondaryAddressFinder`.
///
/// Throws [StateError] unless [preference] names an atDirectory on the
/// loopback interface, before anything connects.
SecondaryAddressFinder atDirectoryOf(AtClientPreference preference) {
  if (!loopbackHosts.contains(preference.rootDomain)) {
    throw StateError('A unit test asked for the atDirectory at '
        '${preference.rootDomain}:${preference.rootPort}; give it one on the '
        'loopback interface, such as defaultAtDirectory or '
        'refusingAtDirectory()');
  }
  return CacheableSecondaryAddressFinder(
      preference.rootDomain, preference.rootPort);
}

/// An atDirectory on the loopback interface, at port 1, where nothing
/// listens, for a test that names one and never reaches it.
SecondaryAddressFinder get defaultAtDirectory =>
    CacheableSecondaryAddressFinder(InternetAddress.loopbackIPv4.address, 1);

/// An atDirectory that refuses every connection: a loopback port nothing
/// listens on.
Future<SecondaryAddressFinder> refusingAtDirectory() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return CacheableSecondaryAddressFinder(
      InternetAddress.loopbackIPv4.address, port);
}
