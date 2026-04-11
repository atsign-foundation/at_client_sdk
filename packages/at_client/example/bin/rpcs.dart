import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/snippets/init_example_context.dart';

const String rpcName = 'some_method.some_interface';

/// Example of simple messaging between atSigns using notifications.
///
/// Sender will send a notification on some namespace (like a 'topic' in
/// pub-sub systems)
///
/// Receiver will listen for notifications on that topic
void main(List<String> args) async {
  stdout.writeln('Messaging');
  ExampleContext c = await getExampleContext(args);
  switch (c.role) {
    case ExampleRole.sender:
      await sender(c);
      return;
    case ExampleRole.receiver:
      await receiver(c);
      break;
  }
}

/// 1. Send an rpc with a reasonable timeout of 30 seconds
/// 2. Send an rpc with an unfeasibly short timeout - should throw exception
/// 3. Send rpc with our magic `'throw':true` value; the server will
//     throw an exception which we will catch here.
Future<void> sender(ExampleContext c) async {
  final rpcClient = AtRpcClient(
    serverAtsign: c.otherAtSigns!.first,
    atClient: c.atClient,
    baseNameSpace: applicationNamespace,
    domainNameSpace: rpcName,
  );

  Map<String, dynamic> responseBody;

  // 1. Send an rpc with a reasonable timeout of 30 seconds
  responseBody =
      await rpcClient.call({'param1': 'foo', 'param2': true}).timeout(
    Duration(seconds: 30),
  );
  stdout.writeln('    -> Received RPC response body: $responseBody');

  // 2. Send rpc with an unfeasibly short timeout - should throw exception
  stdout.writeln('-> Sending rpc with 1-microsecond timeout');
  try {
    responseBody =
        await rpcClient.call({'param1': 'foo', 'param2': true}).timeout(
      Duration(microseconds: 1),
    );
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
        .call({'param1': 'foo', 'param2': true, 'throw': true}).timeout(
      Duration(seconds: 30),
    );
  } catch (e) {
    stdout.writeln('    -> Got error response as expected: $e');
  }
}

Future<void> receiver(ExampleContext c) async {
  AtRpc.server(
    atClient: c.atClient,
    baseNameSpace: applicationNamespace,
    domainNameSpace: rpcName,
    requestHandler: requestHandler,
    allowList: c.otherAtSigns,
    allowAll: c.otherAtSigns == null,
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
