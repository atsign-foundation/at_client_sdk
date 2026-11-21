import 'package:at_client_cli/at_client_cli.dart';

/// Opens a CLIBase on the arguments given, for a test that interrupts it
/// while it waits for an enrollment's approval.
Future<void> main(List<String> args) async {
  await CLIBase.fromCommandLineArgs(args,
      parser: CLIBase.createArgsParser(namespace: 'cli_test'));
}
