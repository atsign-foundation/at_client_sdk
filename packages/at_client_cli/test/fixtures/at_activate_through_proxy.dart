import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;
import 'package:at_client_cli/src/register/register.dart'
    show onboardRegistered;

/// Trusts the certificate at the first argument, then runs at_activate with
/// the arguments after the second: as `AtActivate.main` runs it when the
/// second is `AtActivate`, through `onboardRegistered` when it is
/// `onboardRegistered`, and otherwise as the program the second names. Exits
/// with its code.
Future<void> main(List<String> args) async {
  SecurityContext.defaultContext.setTrustedCertificates(args[0]);
  final arguments = args.sublist(2);
  exit(switch (args[1]) {
    'AtActivate' => await AtActivate.main(arguments),
    'onboardRegistered' => await _onboardRegistered(arguments),
    final program => await auth_cli.main(arguments, program: program),
  });
}

/// `onboardRegistered` for the atSign, CRAM secret and root server
/// [arguments] name, refused with 70 unless that root is a proxy on the
/// loopback interface.
Future<int> _onboardRegistered(List<String> arguments) async {
  final [atSign, cramKey, rootServer] = arguments;
  if (!rootServer.startsWith('proxy:127.0.0.1:')) {
    stderr.writeln('Refused: $rootServer is not a proxy on the loopback '
        'interface');
    return 70;
  }
  return onboardRegistered(atSign, cramKey, rootServer: rootServer);
}
