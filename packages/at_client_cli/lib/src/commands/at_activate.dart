import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;

/// The at_activate tool, for a program that runs it under its own name.
abstract final class AtActivate {
  /// Runs at_activate with [args] and answers its exit code.
  static Future<int> main(List<String> args) => auth_cli.main(args);
}
