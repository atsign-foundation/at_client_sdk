import 'dart:io';

import 'package:at_lookup/at_lookup.dart' show AtCommandExecutor;

/// Keeps the first command an authenticator sends, its `from:`, answering
/// every command with nothing so the authenticator stops there.
class FromRecorder implements AtCommandExecutor {
  String? from;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    from ??= command;
    return '';
  }
}

/// The version the pubspec at [path] declares.
String pubspecVersion([String path = 'pubspec.yaml']) =>
    RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File(path).readAsStringSync())!
        .group(1)!;
