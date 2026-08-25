import 'package:at_auth/src/auth/socket_probe_io.dart';

/// `secureSocketProbe` — see `probe_default.dart` for why this is the branch
/// chosen where `dart:io` is present.
Future<void> defaultProbe(String host, int port) =>
    secureSocketProbe(host, port);
