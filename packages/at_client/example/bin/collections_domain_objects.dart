import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_client_examples/domain_objects.dart';

import 'package:at_client_examples/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Collections');
  ExampleContext c = await getExampleContext(args);

  c.progressController.stream.listen(
    (s) => stdout.writeln('${DateTime.now()} | $s'),
  );

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

  final pets =
      (await c.atClient.collection<Pet>(
          'pets.$applicationNamespace',
          exampleDefaultExpiration,
        ))
        ..registerFactory<Dog>(Dog.fromJson)
        ..registerFactory<Cat>(Cat.fromJson);

  switch (c.role) {
    case ExampleRole.sender:
      await sender(c.atClient, c.otherAtSigns, c.progressController.sink, pets);
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
  Future<void> addAndLog(String label, Pet pet) async {
    progressSink.add('Creating $label, sharing with $otherAtSigns');
    try {
      await pets.create(obj: pet, sharedWith: otherAtSigns);
      progressSink.add('  ...saved.');
    } on CollectionOpException catch (e) {
      for (final r in e.results) {
        progressSink.add(r.toString());
      }
    }
  }

  await addAndLog('a Dog', Dog(name: '${atClient.atSign}\'s dog Rex'));
  await addAndLog('a Cat', Cat(name: '${atClient.atSign}\'s cat Felix'));

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

    for (final pet in await pets.getItems()) {
      progressSink.add('Fetched ${pets.prettyString(pet)}');
    }
    await Future.delayed(Duration(seconds: 3));
  }
}
