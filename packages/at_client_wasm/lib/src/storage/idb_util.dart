import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

Future<T> requestToFuture<T extends JSAny?>(IDBRequest request) {
  final completer = Completer<T>();
  request.onsuccess = (Event event) {
    completer.complete(request.result as T);
  }.toJS;
  request.onerror = (Event event) {
    completer.completeError(request.error ?? Exception('IDBRequest failed'));
  }.toJS;
  return completer.future;
}

Future<void> transactionToFuture(IDBTransaction tx) {
  final completer = Completer<void>();
  tx.oncomplete = (Event event) {
    completer.complete();
  }.toJS;
  void fail(Event event) {
    if (completer.isCompleted) return;
    completer.completeError(tx.error ?? Exception('IDBTransaction aborted'));
  }

  tx.onerror = fail.toJS;
  tx.onabort = fail.toJS;
  return completer.future;
}
