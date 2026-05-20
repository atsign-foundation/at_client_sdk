// Domain objects shared with the TUI example at
// packages/at_client/example/bin/collections_todos.dart. The JSON schema must
// remain byte-compatible so the two apps can share data over the atPlatform.

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

  TodoNote({required this.note});

  factory TodoNote.fromJson(Map<String, dynamic> json) {
    return TodoNote(note: json['note']);
  }

  Map<String, dynamic> toJson() => {'note': note};
}
