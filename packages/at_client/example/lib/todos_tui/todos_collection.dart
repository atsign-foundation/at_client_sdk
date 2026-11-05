import 'package:at_client/at_client.dart';

import '../domain_objects.dart';

/// The namespace the todos examples run in: this CLI and the Flutter todos
/// app, which share todos with each other.
const String todosNamespace = 'todos.demos';

/// The type tag a todo is stored under.
const String todoTypeTag = 'Todo';

/// The preference a todos example's client runs under: post-quantum, in
/// [todosNamespace].
AtClientPreference todosPreference() =>
    AtClientPreference(posture: PqPosture.pqActive)..namespace = todosNamespace;

/// Opens [atClient]'s todos collection the way both todos examples store it.
Future<AtCollection<Todo>> openTodos(AtClient atClient) =>
    atClient.collection<Todo>(
      'todos.${atClient.getPreferences()!.namespace!}',
      const Duration(days: 365),
      eventSource: EventSource.both,
      fromJson: Todo.fromJson,
      typeTag: todoTypeTag,
      cleanupOrphansOnCreation: true,
    );
