import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections - Maps and Strings');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream.listen((s) => stdout.writeln(s));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final AtCollection<Map> maps = c.atClient.collection<Map>(
    'maps.$applicationNamespace',
    exampleDefaultExpiration,
  );
  final AtCollection<String> strings = c.atClient.collection<String>(
    'strings.$applicationNamespace',
    exampleDefaultExpiration,
  );

  switch (c.role) {
    case ExampleRole.sender:
      await sender(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        maps,
        strings,
      );
      break;
    case ExampleRole.receiver:
      await receiver(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        maps,
        strings,
      );
      break;
  }
  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Map> maps,
  AtCollection<String> strings,
) async {
  progressSink.add('Creating a Map, sharing with $otherAtSigns');
  await for (final r in maps.put(
    AtModel.primitive(
      owner: atClient.atSign,
      id: '12345',
      obj: {'isMap': true, 'name': 'my map', 'intValue': 123},
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a String, sharing with $otherAtSigns');
  await for (final r in strings.put(
    AtModel.primitive(
      owner: atClient.atSign,
      id: '12345',
      obj: 'this is just a String',
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  await poll(maps: maps, strings: strings, progressSink: progressSink);
}

Future<void> poll({
  required AtCollection<Map> maps,
  required AtCollection<String> strings,
  required StreamSink<String> progressSink,
}) async {
  while (true) {
    progressSink.add('${DateTime.now().toString()} : Fetching');

    final mapsResponse = await maps.get();
    for (final e in mapsResponse.exceptions) {
      progressSink.add('Exception: $e');
    }
    for (final i in mapsResponse.models) {
      progressSink.add('Fetched ${i.id}.${maps.namespace}${i.owner}'
          ' sharedWith ${i.sharedWith}'
          ' factory type ${i.type}'
          ' runtime type ${i.obj.runtimeType}'
          ' obj ${i.obj}'
          '');
    }

    final stringsResponse = await strings.get();
    for (final e in stringsResponse.exceptions) {
      progressSink.add('Exception: $e');
    }
    for (final i in stringsResponse.models) {
      progressSink.add('Fetched ${i.id}.${strings.namespace}${i.owner}'
          ' sharedWith ${i.sharedWith}'
          ' factory type ${i.type}'
          ' runtime type ${i.obj.runtimeType}'
          ' obj ${i.obj}'
          '');
    }
    await Future.delayed(Duration(seconds: 3));
  }
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Map> maps,
  AtCollection<String> strings,
) async {
  await poll(maps: maps, strings: strings, progressSink: progressSink);
}
