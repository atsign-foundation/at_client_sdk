import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  AtModel.registerFactory(type: 'Dog', factory: Dog.fromJson);
  AtModel.registerFactory(type: 'Cat', factory: Cat.fromJson);

  stdout.writeln('Collections - generic');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream.listen((s) => stdout.writeln(s));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final AtCollection generic = c.atClient.collection(
    'generic.$applicationNamespace',
    exampleDefaultExpiration,
  );

  switch (c.role) {
    case ExampleRole.sender:
      await sender(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        generic,
      );
      break;
    case ExampleRole.receiver:
      await receiver(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        generic,
      );
      break;
  }
  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection generic,
) async {
  progressSink.add('Creating some binary data, sharing with $otherAtSigns');
  await for (final r in generic.put(
    AtModel.primitive(
      owner: atClient.atSign,
      id: 'binary_12345',
      obj: Uint8List.fromList(
          'This is binary data from ${atClient.atSign}'.codeUnits),
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a Dog, sharing with $otherAtSigns');
  await for (final r in generic.put(
    AtModel.domain(
      owner: atClient.atSign,
      id: 'pets_rex',
      type: 'Dog',
      obj: Dog(name: '${atClient.atSign}\'s dog Rex'),
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a Cat, sharing with $otherAtSigns');
  await for (final r in generic.put(
    AtModel.domain(
        owner: atClient.atSign,
        id: 'pets_felix',
        type: 'Cat',
        obj: Cat(name: '${atClient.atSign}\'s cat Felix'),
        sharedWith: otherAtSigns),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a Map, sharing with $otherAtSigns');
  await for (final r in generic.put(
    AtModel.primitive(
      owner: atClient.atSign,
      id: 'map_12345',
      obj: {'isMap': true, 'name': 'my map', 'intValue': 123},
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a String, sharing with $otherAtSigns');
  await for (final r in generic.put(
    AtModel.primitive(
      owner: atClient.atSign,
      id: 'string_12345',
      obj: 'this is just a String',
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  await poll(generic, progressSink);
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection generic,
) async {
  await poll(generic, progressSink);
}

Future<void> poll(
  AtCollection generic,
  StreamSink<String> progressSink,
) async {
  while (true) {
    progressSink.add('${DateTime.now().toString()} : Fetching');

    final getResponse = await generic.get();
    for (final e in getResponse.exceptions) {
      progressSink.add('Exception: $e');
    }
    for (final model in getResponse.models) {
      String msg = 'Fetched ${generic.prettyString(model)}';
      if (model.type == 'binary') {
        msg = '$msg : ${String.fromCharCodes(model.obj)}';
      }
      progressSink.add(msg);
    }
    await Future.delayed(Duration(seconds: 3));
  }
}
