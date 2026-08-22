import 'package:at_auth/src/auth/server_probe.dart';

/// [httpsProbe] — see `probe_default.dart` for why this is the branch chosen
/// where `dart:io` is absent.
Future<void> defaultProbe(String host, int port) => httpsProbe(host, port);
