import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:chalkdart/chalk.dart';
import 'common.dart';

void main(List<String> args) async {
  try {
    var argsParser = CLIBase.argsParser
      ..addOption('service-atsign',
          mandatory: true,
          help: "the atSign of the service this client is using");

    var serviceAtsign = argsParser.parse(args)['service-atsign'];

    var atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;

    var rpc = AtRpcClient(
        atClient: atClient,
        baseNameSpace: atClient.getPreferences()!.namespace!,
        domainNameSpace: policyRequestNamespace,
        serverAtsign: serviceAtsign);

    stdout.writeln('Can make three types of request.');
    for (final rt in RequestType.values) {
      stdout.writeln('  ${rt.index + 1}. ${rt.name}');
    }
    stdout.writeln();
    while (true) {
      stdout.write(chalk.brightBlue('Enter request type number: '));
      int reqType = int.parse(stdin.readLineSync()!.trim());
      if (reqType < 1 || reqType > RequestType.values.length) {
        stdout.writeln(chalk.red('Invalid request type'));
        continue;
      }

      try {
        var response = await rpc
            .call({'reqType': RequestType.values[reqType - 1].name}).timeout(
                Duration(seconds: 15));

        stdout.writeln(chalk.green(response));
      } on TimeoutException {
        stderr.writeln(chalk.brightRed('timed out waiting for response'));
      } catch (e) {
        stderr.writeln(chalk.brightRed(e));
      }
    }
  } catch (e) {
    print(e);
    print(CLIBase.argsParser.usage);
  }
}
