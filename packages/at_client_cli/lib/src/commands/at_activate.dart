import 'package:at_client_cli/src/commands/auth_cli.dart' as auth_cli;

/// The at_activate tool, for a program that runs it under its own name: the
/// program names itself and its version on every `from:` at_activate's
/// clients send to authenticate.
abstract final class AtActivate {
  /// Runs at_activate with [args] as [program] at [programVersion], and
  /// answers its exit code; at_client_cli's version when [programVersion] is
  /// null.
  static Future<int> main(List<String> args,
          {String program = 'at_activate', String? programVersion}) =>
      auth_cli.main(args, program: program, programVersion: programVersion);
}
