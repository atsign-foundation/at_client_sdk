import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections - binary data');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream
      .listen((s) => stdout.writeln('${DateTime.now()} | $s'));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final AtCollection<Uint8List> binaries = c.atClient.collection<Uint8List>(
    'binary.$applicationNamespace',
    exampleDefaultExpiration,
  );

  switch (c.role) {
    case ExampleRole.sender:
      await sender(
          c.atClient, c.otherAtSigns, c.progressController.sink, binaries);
      break;
    case ExampleRole.receiver:
      await receiver(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        binaries,
      );
      break;
  }
  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Uint8List> binaries,
) async {
  progressSink.add('Creating some binary data, sharing with $otherAtSigns');
  final data = Uint8List.fromList(
      'This is binary data from ${atClient.atSign}'.codeUnits);

  for (final r in await binaries.put(
    binaries.create(
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
  AtCollection<Uint8List> binaries,
  StreamSink<String> progressSink,
) async {
  while (true) {
    progressSink.add('${DateTime.now().toString()} : Fetching');

    final getResponse = await binaries.getItems();
    for (final e in getResponse.exceptions) {
      progressSink.add('Exception: $e');
    }
    for (final item in getResponse.items) {
      String msg = '==> Fetched ${binaries.prettyString(item)}';
      if (item.type == 'binary') {
        msg = '$msg : ${String.fromCharCodes(item.obj)}';
      }
      progressSink.add(msg);
    }
    progressSink.add('');
    await Future.delayed(Duration(seconds: 3));
  }
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Uint8List> binaries,
) async {
  await poll(binaries, progressSink);
}
