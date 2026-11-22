import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';

/// Runs at_activate with the arguments given, trusting for its TLS
/// connections the certificate at the path `AT_ACTIVATE_TEST_CERT` names.
/// Exits with at_activate's code.
Future<void> main(List<String> args) async {
  final cert = Platform.environment['AT_ACTIVATE_TEST_CERT'];
  if (cert != null) {
    SecurityContext.defaultContext.setTrustedCertificates(cert);
  }
  exit(await AtActivate.main(args));
}
