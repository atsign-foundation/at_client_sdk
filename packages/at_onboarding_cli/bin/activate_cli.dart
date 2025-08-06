import 'dart:io';

import 'package:at_onboarding_cli/src/cli/auth_cli.dart' as auth_cli;

Future<void> main(List<String> args) async {
  exit(await auth_cli.main(args));
}
