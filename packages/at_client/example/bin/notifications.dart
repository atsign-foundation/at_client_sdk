// - simple messaging: `@alice` sends message to `@bob`
// - messaging: send
// - rpc: atRpc
import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';

import 'package:at_client_examples/snippets/init_example_context.dart';

const String subNamespace = 'fire.and.forget';

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
      break;
    case ExampleRole.receiver:
      await receiver(c);
      break;
  }
  exit(0);
}

Future<void> sender(ExampleContext c) async {
  final String msgId = DateTime.now().microsecondsSinceEpoch.toString();
  String namespace = '$msgId.$subNamespace.$applicationNamespace';
  await Future.wait(c.otherAtSigns!.map((otherAtsign) {
    String msg;
    // Basic messaging - send notification, fire and forget
    msg = 'Simple fire and forget message with ID part';
    stdout.writeln('-> Sending $msg to $otherAtsign on $namespace');
    return c.atClient.notificationService.send(
      to: otherAtsign,
      namespace: namespace,
      body: msg,
    );
  }));
  await Future.wait(c.otherAtSigns!.map((otherAtsign) {
    String msg;
    // Basic messaging - send notification, fire and forget
    msg = 'Simple fire and forget message without ID part';
    String namespace = '$subNamespace.$applicationNamespace';
    stdout.writeln('-> Sending $msg to $otherAtsign on $namespace');
    return c.atClient.notificationService.send(
      to: otherAtsign,
      namespace: namespace,
      body: msg,
    );
  }));
}

Future<void> receiver(ExampleContext c) async {
  Completer done = Completer();
  // ignore: unused_local_variable
  StreamSubscription<AtNotification>? sub;
  sub = c.atClient.notificationService
      .subscribeFiltered(
    acceptedSenders: c.otherAtSigns,
    namespace: '$subNamespace.$applicationNamespace',
  )
      .listen((n) {
    stdout.writeln('-> Received ${n.value} from ${n.from} : ${n.key}');
  });
  await done.future;
}
