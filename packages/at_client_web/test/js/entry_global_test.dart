@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';

import '../../web/at_client_bridge_entry.dart' as entry;

void main() {
  test('the entry installs one global whose only member is create', () {
    entry.main();
    addTearDown(() => globalContext.delete('__atsignAtClientWeb'.toJS));

    final global = globalContext['__atsignAtClientWeb'];
    expect(global, isA<JSObject>());
    final names = (globalContext['Object']! as JSObject)
        .callMethod('getOwnPropertyNames'.toJS, global!)! as JSArray<JSString>;
    expect([for (final name in names.toDart) name.toDart], ['create']);
  });
}
