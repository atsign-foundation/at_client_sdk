import 'dart:io';

import 'package:at_client_cli/at_client_cli.dart' show AtActivate;

Future<void> main(List<String> args) async => exit(await AtActivate.main(args));
