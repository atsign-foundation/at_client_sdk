import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'setup_lock.dart';

/// A [SetupLock] over `navigator.locks`.
class WebSetupLock implements SetupLock {
  @override
  Future<T> run<T>(String name, Future<T> Function() body) async {
    final locks =
        (window.navigator as JSObject).getProperty<JSAny?>('locks'.toJS);
    if (!locks.isA<JSObject>()) {
      throw UnsupportedError('navigator.locks is unavailable');
    }
    final result = Completer<T>();
    JSPromise<JSAny?> hold(JSAny? _) => (() async {
          try {
            result.complete(await body());
          } on Object catch (e, s) {
            result.completeError(e, s);
          }
          return null;
        }())
            .toJS;
    await (locks as JSObject)
        .callMethod<JSPromise<JSAny?>>('request'.toJS, name.toJS, hold.toJS)
        .toDart;
    return result.future;
  }
}
