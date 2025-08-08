import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_policy/at_policy.dart';
import 'package:chalkdart/chalk.dart';

void main(List<String> args) async {
  try {
    var atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;

    PolicyService ps = PolicyService(
      baseNamespace: atClient.getPreferences()!.namespace!,
      loggingAtsign: atClient.getCurrentAtSign()!,
      allowList: {},
      allowAll: true,
      atClient: atClient,
      handler: DemoPolicyRequestHandler(),
    );

    await ps.run();
  } catch (e) {
    print(e);
    print(CLIBase.argsParser.usage);
  }
}

class DemoPolicyRequestHandler implements PolicyRequestHandler {
  @override
  Future<PolicyResponse> getPolicyDetails(PolicyRequest req) async {
    stdout.writeln(chalk.blue('Received request $req'));

    stdout.write('(A)pprove or (D)eny? : ');
    String decision = '';
    while (decision.isEmpty) {
      decision = stdin.readLineSync()!;
    }
    final bool approved = decision.toLowerCase().startsWith('a');

    if (approved) {
      List<PolicyDetail> details = [];
      for (var i in req.intents) {
        details.add(PolicyDetail(
          intent: i.intent,
          info: {'authorized': true},
        ));
      }
      return PolicyResponse(
        message: 'manually approved',
        policyDetails: details,
      );
    } else {
      return PolicyResponse(message: 'nope', policyDetails: []);
    }
  }
}
