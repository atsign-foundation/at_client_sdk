import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:at_policy/at_policy.dart';
import 'package:chalkdart/chalk.dart';
import 'common.dart';

void main(List<String> args) async {
  try {
    var argsParser = CLIBase.argsParser
      ..addOption('policy-atsign',
          mandatory: true, help: "the atSign of the policy service");

    var policyAtsign = argsParser.parse(args)['policy-atsign'];

    var atClient = (await CLIBase.fromCommandLineArgs(args)).atClient;

    var policyRpcClient = AtRpcClient(
      atClient: atClient,
      baseNameSpace: atClient.getPreferences()!.namespace!,
      domainNameSpace: policyRequestNamespace,
      serverAtsign: policyAtsign,
    );

    var thisRpcServer = AtRpc(
      atClient: atClient,
      baseNameSpace: atClient.getPreferences()!.namespace!,
      domainNameSpace: policyRequestNamespace,
      callbacks: DemoRpcServer(
        myAtsign: atClient.getCurrentAtSign()!,
        policyAtsign: policyAtsign,
        policyRpcClient: policyRpcClient,
      ),
      allowList: {},
      allowAll: true,
    );

    thisRpcServer.start();
  } catch (e) {
    print(e);
    print(CLIBase.argsParser.usage);
  }
}

class DemoRpcServer implements AtRpcCallbacks {
  String myAtsign;
  String policyAtsign;
  AtRpcClient policyRpcClient;

  DemoRpcServer({
    required this.myAtsign,
    required this.policyAtsign,
    required this.policyRpcClient,
  });

  @override
  Future<AtRpcResp> handleRequest(AtRpcReq request, String fromAtSign) async {
    stdout.writeln(chalk.blue('Received request ${request.toJson()}'));
    RequestType rt;

    try {
      rt = RequestType.values.byName(request.payload['reqType']);
    } catch (e) {
      return AtRpcResp(
          reqId: request.reqId,
          respType: AtRpcRespType.error,
          payload: {},
          message: 'Invalid request ${request.payload}');
    }

    PolicyRequest polReq = PolicyRequest(
        serviceAtsign: myAtsign,
        serviceName: 'example_service_001',
        serviceGroupName: 'example_service',
        clientAtsign: fromAtSign,
        intents: [PolicyIntent(intent: rt.name, params: {})]);

    stderr.writeln('Sending policy check request : $polReq');
    Map<String, dynamic> policyResponse =
        await policyRpcClient.call(polReq.toJson());
    stderr.writeln('Received policy info : $policyResponse');
    return AtRpcResp(
      reqId: request.reqId,
      respType: AtRpcRespType.success,
      payload: {'some': 'payload'},
      message: 'Not yet implemented', // TODO
    );
  }

  @override
  Future<void> handleResponse(AtRpcResp response) async {
    // Not expecting to receive responses
    throw UnimplementedError();
  }
}
