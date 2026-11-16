import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart';
import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;

/// Trusts the certificate at the first argument, then runs at_activate with
/// the arguments after the second as the program the second names; as
/// `AtActivate.main` runs it when the second is `AtActivate`, or naming
/// `<program>` at `<version>` when it is `AtActivate:<program>:<version>`.
/// Exits with its code.
Future<void> main(List<String> args) async {
  SecurityContext.defaultContext.setTrustedCertificates(args[0]);
  final arguments = args.sublist(2);
  exit(switch (args[1].split(':')) {
    ['AtActivate'] => await AtActivate.main(arguments),
    ['AtActivate', final program, final version] => await AtActivate.main(
        arguments,
        program: program,
        programVersion: version),
    _ => await auth_cli.main(arguments, program: args[1]),
  });
}
