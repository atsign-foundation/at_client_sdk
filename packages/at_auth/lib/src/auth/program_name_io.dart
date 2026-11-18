import 'dart:io';

import 'package:at_auth/src/auth/program_name.dart';

/// The name of the program file this process runs, from [Platform.script].
String derivedProgramName() => programNameOf(() => Platform.script);
