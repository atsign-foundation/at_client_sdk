/// at_client for a native Dart program: everything in `at_client.dart`, plus
/// the pieces that need `dart:io` — keys in a file, connections over TLS on
/// TCP, and the atDirectory asked over TLS.
///
/// `at_client.dart` names none of these, so a program that imports it alone
/// compiles for any platform and supplies its own.
library;

export 'package:at_client/at_client.dart';
export 'package:at_auth/at_auth_io.dart' show FileAtKeysIo;
export 'package:at_lookup/at_lookup_io.dart'
    show CacheableSecondaryAddressFinder, secureSocketLookUps;
