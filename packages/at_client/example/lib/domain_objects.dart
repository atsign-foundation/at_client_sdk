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
