import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections - binary data');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream.listen((s) => stdout.writeln(s));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  switch (c.role) {
    case ExampleRole.sender:
      await sender(c.atClient, c.otherAtSigns, c.progressController.sink);
      break;
    case ExampleRole.receiver:
      await receiver(c.atClient, c.otherAtSigns, c.progressController.sink);
      break;
  }
  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
) async {
  final Collection<Uint8List> binaries =
      atClient.collection<Uint8List>('binary.$applicationNamespace');

  progressSink.add('Creating some binary data, sharing with $otherAtSigns');
  final data = Uint8List.fromList(
      'This is binary data from ${atClient.atSign}'.codeUnits);

  await for (final r in binaries.put(
    Model.primitive(
      owner: atClient.atSign,
      id: '12345',
      obj: data,
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  await poll(binaries, progressSink);
}

Future<void> poll(
  Collection c,
  StreamSink<String> progressSink,
) async {
  while (true) {
    progressSink.add('${DateTime.now().toString()} : Fetching');

    final getResponse = await c.get();
    for (final e in getResponse.exceptions) {
      progressSink.add('Exception: $e');
    }
    for (final i in getResponse.models) {
      progressSink.add('Fetched ${i.id}.${c.namespace}${i.owner}'
          ' sharedWith ${i.sharedWith}'
          ' type ${i.type}'
          ' with length ${i.obj.length} bytes'
          ' : ${String.fromCharCodes(i.obj)}'
          '');
    }
    await Future.delayed(Duration(seconds: 3));
  }
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
) async {
  final Collection binaries =
      atClient.collection<Uint8List>('binary.$applicationNamespace');

  await poll(binaries, progressSink);
}
