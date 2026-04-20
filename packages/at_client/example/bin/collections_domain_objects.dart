import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream
      .listen((s) => stdout.writeln('${DateTime.now()} | $s'));

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  AtCollection.registerFactory(type: 'Dog', factory: Dog.fromJson);
  AtCollection.registerFactory(type: 'Cat', factory: Cat.fromJson);
  final pets = c.atClient.collection<Pet>(
    'pets.$applicationNamespace',
    exampleDefaultExpiration,
  );

  switch (c.role) {
    case ExampleRole.sender:
      await sender(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        pets,
      );
      break;
    case ExampleRole.receiver:
      await receiver(
        c.atClient,
        c.otherAtSigns,
        c.progressController.sink,
        pets,
      );
      break;
  }
  exit(0);
}

Future<void> sender(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Pet> pets,
) async {
  progressSink.add('Creating a Dog, sharing with $otherAtSigns');
  for (final r in await pets.put(
    pets.create(
      type: 'Dog',
      obj: Dog(name: '${atClient.atSign}\'s dog Rex'),
      sharedWith: otherAtSigns,
    ),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  progressSink.add('Creating a Cat, sharing with $otherAtSigns');
  for (final r in await pets.put(
    pets.create(
        type: 'Cat',
        obj: Cat(name: '${atClient.atSign}\'s cat Felix'),
        sharedWith: otherAtSigns),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
  )) {
    progressSink.add(r.toString());
  }

  await poll(pets, progressSink);
}

Future<void> receiver(
  AtClient atClient,
  Set<Atsign>? otherAtSigns,
  StreamSink<String> progressSink,
  AtCollection<Pet> pets,
) async {
  await poll(pets, progressSink);
}

Future<void> poll(
  AtCollection<Pet> pets,
  StreamSink<String> progressSink,
) async {
  while (true) {
    progressSink.add('${DateTime.now().toString()} : Fetching');

    for (final pet in (await pets.getItems()).items) {
      progressSink.add('Fetched ${pets.prettyString(pet)}');
    }
    await Future.delayed(Duration(seconds: 3));
  }
}
