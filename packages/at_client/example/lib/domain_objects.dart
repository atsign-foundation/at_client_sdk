class Todo {
  String title;
  String description;
  bool done;
  DateTime? dueDate;

  Todo({
    required this.title,
    required this.description,
    this.done = false,
    this.dueDate,
  });

  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      title: json['title'],
      description: json['description'],
      done: json['done'] ?? false,
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'done': done,
    if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
  };
}

class TodoNote {
  String note;
  String todoId;

  TodoNote({required this.note, required this.todoId});

  factory TodoNote.fromJson(Map<String, dynamic> json) {
    return TodoNote(note: json['note'], todoId: json['todoId']);
  }

  Map<String, dynamic> toJson() => {'note': note, 'todoId': todoId};
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
