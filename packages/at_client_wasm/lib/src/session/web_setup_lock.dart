import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart';

import 'setup_lock.dart';

/// Thrown when the lock named [lockName] is not granted within the
/// acquisition timeout.
class SetupLockTimeoutException implements Exception {
  /// Creates the exception for [lockName].
  const SetupLockTimeoutException(this.lockName);

  /// The name of the lock that was not granted.
  final String lockName;

  @override
  String toString() => 'SetupLockTimeoutException: $lockName was not granted';
}

/// A [SetupLock] over `navigator.locks`.
///
/// [acquireTimeout] bounds only the wait for the lock; the section running
/// under it is not bounded.
class WebSetupLock implements SetupLock {
  /// Creates a lock whose acquisition aborts after [acquireTimeout].
  WebSetupLock({this.acquireTimeout = const Duration(minutes: 2)});

  /// The longest a [run] waits to be granted the lock.
  final Duration acquireTimeout;

  @override
  Future<T> run<T>(String name, Future<T> Function() body) async {
    final locks =
        (window.navigator as JSObject).getProperty<JSAny?>('locks'.toJS);
    if (!locks.isA<JSObject>()) {
      throw UnsupportedError('navigator.locks is unavailable');
    }
    final result = Completer<T>();
    final controller = AbortController();
    var timedOut = false;
    final timer = Timer(acquireTimeout, () {
      timedOut = true;
      controller.abort();
    });
    JSPromise<JSAny?> hold(JSAny? _) => (() async {
          timer.cancel();
          try {
            result.complete(await body());
          } on Object catch (e, s) {
            result.completeError(e, s);
          }
          return null;
        }())
            .toJS;
    final options = JSObject()..setProperty('signal'.toJS, controller.signal);
    try {
      await (locks as JSObject)
          .callMethod<JSPromise<JSAny?>>(
              'request'.toJS, name.toJS, options, hold.toJS)
          .toDart;
    } on Object {
      if (timedOut) throw SetupLockTimeoutException(name);
      rethrow;
    } finally {
      timer.cancel();
    }
    return result.future;
  }
}
