import 'dart:async';

import 'package:at_client/at_client.dart';

import '../domain_objects.dart';

/// Parent+children snapshot emitted by [Query.watchWithSub] — one
/// todo paired with its current notes.
typedef TodoWithNotes =
    ({CItem<Todo> parent, List<CItem<TodoNote>> children});

/// Which pane currently owns keyboard focus. `list` is the default;
/// `detail` is entered via Enter or Right-arrow so the user can read
/// or scroll through the detail pane; Esc / Left-arrow return.
enum Pane { list, detail }

/// Which modal overlay (if any) is currently active. Only one modal
/// can be open at a time; it steals keyboard focus from the main
/// view and is dismissed with Esc.
enum Modal {
  none,
  commandMenu,
  help,
  find,
  createTodo,
  editTodo,
  addNote,
  share,
  schedule,
  setDue,
  confirmDeleteTodo,
}

/// One row in the command menu. Each command is a (label, hint,
/// invoke) triple — the hint column renders the equivalent single-
/// key shortcut when one exists.
typedef Command =
    ({String label, String hint, FutureOr<void> Function() invoke});
