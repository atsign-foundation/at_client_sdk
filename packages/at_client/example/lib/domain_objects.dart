class Todo {
  String title;
  String description;

  Todo({required this.title, required this.description});

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(title: json['title'], description: json['description']);
  }

  Map<String, dynamic> toJson() => {'title': title, 'description': description};
}

class TodoNote {
  String note;

  TodoNote({required this.note});

  factory TodoNote.fromJson(Map<String, dynamic> json) {
    return TodoNote(note: json['note']);
  }

  Map<String, dynamic> toJson() => {'note': note};
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
