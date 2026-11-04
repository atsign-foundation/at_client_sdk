import 'dart:io';

import 'package:at_client/at_client_io.dart';

/// The atDirectory [preference] names, asked over TLS: what a native program
/// passes as a client's `secondaryAddressFinder`.
SecondaryAddressFinder atDirectoryOf(AtClientPreference preference) =>
    CacheableSecondaryAddressFinder(preference.rootDomain, preference.rootPort);

/// The atDirectory a default [AtClientPreference] names.
SecondaryAddressFinder get defaultAtDirectory =>
    atDirectoryOf(AtClientPreference());

/// An atDirectory that refuses every connection: a loopback port nothing
/// listens on.
Future<SecondaryAddressFinder> refusingAtDirectory() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return CacheableSecondaryAddressFinder(
      InternetAddress.loopbackIPv4.address, port);
}
