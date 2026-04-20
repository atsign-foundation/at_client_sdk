import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/init_example_context.dart';

const String rpcName = 'some_method.some_interface';

void main(List<String> args) async {
  stdout.writeln('Messaging');
  ExampleContext c = await getExampleContext(args);
  switch (c.role) {
    case ExampleRole.sender:
      await sender(c.atClient, c.otherAtSigns);
      return;
    case ExampleRole.receiver:
      await receiver(c.atClient, c.otherAtSigns);
      break;
  }
}

/// 1. Send an rpc with a reasonable timeout of 30 seconds
/// 2. Send an rpc with an unfeasibly short timeout - should throw exception
/// 3. Send rpc with our magic `'throw':true` value; the server will
//     throw an exception which we will catch here.
Future<void> sender(AtClient atClient, Set<Atsign>? otherAtSigns) async {
  final rpcClient = AtRpcClient(
    serverAtsign: otherAtSigns!.first,
    atClient: atClient,
    baseNameSpace: applicationNamespace,
    domainNameSpace: rpcName,
  );

  Map<String, dynamic> responseBody;

  // 1. Send an rpc with a reasonable timeout of 30 seconds
  responseBody = await rpcClient
      .call({'param1': 'foo', 'param2': true})
      .timeout(Duration(seconds: 30));
  stdout.writeln('    -> Received RPC response body: $responseBody');

  // 2. Send rpc with an unfeasibly short timeout - should throw exception
  stdout.writeln('-> Sending rpc with 1-microsecond timeout');
  try {
    responseBody = await rpcClient
        .call({'param1': 'foo', 'param2': true})
        .timeout(Duration(microseconds: 1));
  } on TimeoutException catch (_) {
    stdout.writeln(
      '    -> Sent RPC with timeout of 1 microsecond;'
      ' got timeout exception as expected',
    );
  }

  // 3. Send rpc with our magic `'throw':true` value; the server should
  // throw an exception which we will catch here.
  stdout.writeln('-> Sending rpc request where we expect an error response');
  try {
    await rpcClient
        .call({'param1': 'foo', 'param2': true, 'throw': true})
        .timeout(Duration(seconds: 30));
  } catch (e) {
    stdout.writeln('    -> Got error response as expected: $e');
  }
}

/// Creates an [AtRpcServer] and starts it with [requestHandler] as the
/// request-handling function.
Future<void> receiver(AtClient atClient, Set<Atsign>? otherAtSigns) async {
  AtRpc.server(
    atClient: atClient,
    baseNameSpace: applicationNamespace,
    domainNameSpace: rpcName,
    requestHandler: requestHandler,
    allowList: otherAtSigns,
    allowAll: otherAtSigns == null,
    enableRequestMutex: true,
  ).start();
}

Future<AtRpcResp> requestHandler(AtRpcReq request, String fromAtSign) async {
  stdout.writeln('-> Received ${request.payload} from $fromAtSign');
  if (request.payload['throw'] == true) {
    throw ('Throwing exception as requested');
  }
  return AtRpcResp(
    reqId: request.reqId,
    respType: AtRpcRespType.success,
    payload: {
      'response': {'success': true, 'requestAsReceived': request.payload},
    },
    message: 'Success',
  );
}
