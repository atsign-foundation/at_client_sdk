import 'dart:async';
import 'dart:io';

import 'package:at_client/at_client.dart';

import 'package:at_client_examples/snippets/init_example_context.dart';

void main(List<String> args) async {
  stdout.writeln('Messaging');
  Model.factories['Dog'] = Dog.fromJson;
  Model.factories['Cat'] = Cat.fromJson;
  ExampleContext c = await getExampleContext(args);

  c.atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;
  switch (c.role) {
    case ExampleRole.sender:
      await sender(c.atClient, c.otherAtSigns);
      break;
    case ExampleRole.receiver:
      await receiver(c.atClient, c.otherAtSigns);
      break;
  }
  exit(0);
}

Future<void> sender(AtClient atClient, Set<Atsign>? otherAtSigns) async {
  final pets = atClient.collection<Pet>('pets.$applicationNamespace');

  stdout.writeln('Creating a Dog, sharing with $otherAtSigns');
  final rex = Dog(name: 'Rex');
  // stdout.writeln(jsonEncode(rex));

  final m = Model(owner: atClient.atSign, id: 'rex', type: 'Dog', obj: rex);
  // stdout.writeln(jsonEncode(m));

  await for (final r in pets.put(
    m,
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
    shareWith: otherAtSigns,
  )) {
    stdout.writeln(r);
  }

  stdout.writeln('Creating a Cat, sharing with $otherAtSigns');
  final felix = Cat(name: 'Felix');
  await for (final r in pets.put(
    Model(owner: atClient.atSign, id: 'felix', type: 'Cat', obj: felix),
    expiresAt: DateTime.now().add(Duration(seconds: 10)),
    shareWith: otherAtSigns,
  )) {
    stdout.writeln(r);
  }

  while (true) {
    stdout.writeln('${DateTime.now().toString()} : Fetching');
    await for (final pet in pets.get()) {
      stdout.writeln('Fetched $pet');
    }
    await Future.delayed(Duration(seconds: 3));
  }
}

Future<void> receiver(AtClient atClient, Set<Atsign>? otherAtSigns) async {
  return sender(atClient, otherAtSigns);
}

abstract class Pet {
  final String name;

  Pet({required this.name});

  String get sound;

  Map<String, dynamic> toJson();

  @override
  String toString() {
    return 'Pet{name: $name}';
  }
}

class Dog extends Pet {
  Dog({required super.name});

  @override
  String get sound => "Woof!";

  factory Dog.fromJson(Map<String, dynamic> json) {
    return Dog(name: json['name']);
  }

  @override
  Map<String, dynamic> toJson() => {'name': name};

  @override
  String toString() {
    return 'Dog{name: $name}';
  }
}

class Cat extends Pet {
  Cat({required super.name});

  @override
  String get sound => "Meoow!";

  factory Cat.fromJson(Map<String, dynamic> json) {
    return Cat(name: json['name']);
  }

  @override
  Map<String, dynamic> toJson() => {'name': name};

  @override
  String toString() {
    return 'Cat{name: $name}';
  }
}
