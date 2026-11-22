import 'dart:io';

import 'package:at_client/at_client_io.dart';

/// The hosts a unit test's atDirectory may be on.
const Set<String> loopbackHosts = {'127.0.0.1', 'localhost', '::1'};

/// The atDirectory [preference] names, asked over TLS: what a native program
/// passes as a client's `secondaryAddressFinder`.
///
/// Throws [StateError] unless [preference] names an atDirectory on the
/// loopback interface, before anything connects.
SecondaryAddressFinder atDirectoryOf(AtClientPreference preference) =>
    _loopbackAtDirectory(preference.rootDomain, preference.rootPort);

/// The atDirectory at [host]:[port], asked over TLS; throws [StateError]
/// unless [host] is on the loopback interface.
SecondaryAddressFinder _loopbackAtDirectory(String host, int port) {
  if (!loopbackHosts.contains(host)) {
    throw StateError('A unit test asked for the atDirectory at $host:$port; '
        'give it one on the loopback interface, such as defaultAtDirectory or '
        'refusingAtDirectory()');
  }
  return CacheableSecondaryAddressFinder(host, port);
}

/// [secureSocketLookUps] for a unit test: a connection asked for with no
/// `secondaryAddressFinder` asks the atDirectory its root names, and throws
/// [StateError], before anything connects, unless that root is on the
/// loopback interface.
AtLookUpFactory loopbackLookUps() => (
        {required atSign,
        required rootDomain,
        required authenticator,
        secondaryAddressFinder}) =>
    secureSocketLookUps()(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        secondaryAddressFinder: secondaryAddressFinder ??
            _loopbackAtDirectory(rootDomain.rootDomain, rootDomain.rootPort));

/// An atDirectory on the loopback interface, at port 1, where nothing
/// listens, for a test that names one and never reaches it.
SecondaryAddressFinder get defaultAtDirectory =>
    _loopbackAtDirectory(InternetAddress.loopbackIPv4.address, 1);

/// A preference naming the atDirectory [defaultAtDirectory] is: port 1 on
/// the loopback interface, where nothing listens.
AtClientPreference loopbackPreference() => AtClientPreference()
  ..rootDomain = InternetAddress.loopbackIPv4.address
  ..rootPort = 1;

/// An atDirectory that refuses every connection: a loopback port nothing
/// listens on.
Future<SecondaryAddressFinder> refusingAtDirectory() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return _loopbackAtDirectory(InternetAddress.loopbackIPv4.address, port);
}
