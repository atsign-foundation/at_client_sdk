<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

[![pub package](https://img.shields.io/pub/v/at_sync_ui_flutter)](https://pub.dev/packages/at_sync_ui_flutter) [![](https://img.shields.io/static/v1?label=Backend&message=atPlatform&color=<COLOR>)](https://atsign.dev) [![](https://img.shields.io/static/v1?label=Publisher&message=Atsign&color=F05E3E)](https://atsign.com) [![gitHub license](https://img.shields.io/badge/license-BSD3-blue.svg)](./LICENSE)

## Deprecated

`at_sync_ui_flutter` is deprecated. Version `1.2.0` is the final minor
release and exists to keep existing apps compiling while they migrate away
from foreground sync progress UI.

New Flutter apps should use `AtCollection<T>` and `Query.watch()` from
`at_client`. Collections are backed by the local synced store by default, and
their streams re-emit when local or remote updates arrive. In most screens,
the UI should listen to collection streams directly instead of showing a
global "sync in progress" indicator.

## Migration

Use collection streams as the app-facing state source:

```dart
StreamBuilder<List<CItem<Todo>>>(
  stream: todos.query().where((todo) => !todo.obj.done).watch(),
  builder: (context, snapshot) {
    if (snapshot.hasError) {
      return ErrorView(error: snapshot.error!);
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = snapshot.data!;
    if (items.isEmpty) {
      return const EmptyTodosView();
    }

    return TodoList(items: items);
  },
)
```

For worked examples, see:

- Dart and CLI collection examples:
  [`packages/at_client/example/bin/collections_*.dart`](https://github.com/atsign-foundation/at_client_sdk/tree/trunk/packages/at_client/example/bin)
- Flutter reference app:
  [`packages/at_client_flutter/examples/todos`](https://github.com/atsign-foundation/at_client_sdk/tree/trunk/packages/at_client_flutter/examples/todos)

## Legacy API

The existing `AtSyncUIService`, Material widgets, and Cupertino widgets remain
available in this release for compatibility, but they are deprecated and should
not be used in new code.

## Open source usage and contributions

This is  open source code, so feel free to use it as is, suggest changes or 
enhancements or create your own version. See [CONTRIBUTING.md](https://github.com/atsign-foundation/at_widgets/blob/trunk/CONTRIBUTING.md) for detailed guidance on how to setup tools, tests and make a pull request.
