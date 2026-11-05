import 'package:at_client_cli/src/register/register.dart' as register;

/// The at_register tool, for a program that runs it under its own name.
abstract final class AtRegister {
  /// Runs at_register with [args].
  static Future<void> main(List<String> args) => register.main(args);
}
