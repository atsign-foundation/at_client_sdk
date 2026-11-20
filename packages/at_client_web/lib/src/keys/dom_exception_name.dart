import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The `name` of [error] when it is a JS object whose `name` is a string, as
/// a `DOMException` rejection is; null for anything else.
String? domExceptionName(Object error) {
  try {
    final name = (error as JSObject).getProperty<JSAny?>('name'.toJS);
    return name.isA<JSString>() ? (name as JSString).toDart : null;
  } on Object {
    return null;
  }
}
