/// The shared-monitor ports on a browser: Web Locks, `BroadcastChannel`,
/// and the page's visibility, show and online events.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import '../shared_monitor/shared_monitor_ports.dart';

/// [MonitorLock] over `navigator.locks`.
///
/// A request holds its lock until its grant is released: Web Locks waits on
/// the promise the grant callback returns, and that promise resolves on
/// release. A request aborted while it waits fails with [LockRequestAborted];
/// one whose lock another tab steals sees its grant's `lost` complete, which
/// Web Locks reports by rejecting the stolen holder's request. Web Locks
/// refuses `steal` together with a `signal`, so a stealing request cannot be
/// aborted; it is granted at once in any case.
class BrowserMonitorLock implements MonitorLock {
  const BrowserMonitorLock();

  @override
  LockRequest request(String name, {bool steal = false}) =>
      _BrowserLockRequest(name, steal: steal);
}

class _BrowserLockRequest implements LockRequest {
  _BrowserLockRequest(this.name, {required bool steal}) {
    final options =
        steal ? LockOptions(steal: true) : LockOptions(signal: _abort.signal);
    JSPromise<JSAny?> onGranted(JSAny? lock) {
      _granted.complete(_grant);
      return _released.future.toJS;
    }

    _done = window.navigator.locks
        .request(name, options, onGranted.toJS)
        .toDart
        .then((_) {}, onError: (Object e) {
      if (_granted.isCompleted) {
        // Held and rejected: another tab took the lock with `steal`.
        if (!_grant._lost.isCompleted) _grant._lost.complete();
      } else if (_isAbort(e)) {
        _granted.completeError(LockRequestAborted(name));
      } else {
        _granted.completeError(e);
      }
    });
  }

  final String name;
  final _abort = AbortController();
  final _granted = Completer<LockGrant>();
  final _released = Completer<void>();
  late final _grant = _BrowserLockGrant(this);

  /// The request's own promise: resolved once the lock is released, rejected
  /// when it is aborted or stolen.
  late final Future<void> _done;

  /// Whether [e], the reason a `request()` promise rejected with, is Web
  /// Locks' `AbortError`: the request's signal fired while it waited.
  static bool _isAbort(Object e) {
    // `JSPromise.toDart` rejects with the JS reason as it is.
    // ignore: invalid_runtime_check_with_js_interop_types
    if (e is! JSObject || !e.isA<DOMException>()) return false;
    return (e as DOMException).name == 'AbortError';
  }

  @override
  Future<LockGrant> get granted => _granted.future;

  @override
  void abort() => _abort.abort();
}

class _BrowserLockGrant implements LockGrant {
  _BrowserLockGrant(this._request);

  final _BrowserLockRequest _request;
  final _lost = Completer<void>();

  @override
  Future<void> get lost => _lost.future;

  /// Lets the lock go and waits until Web Locks has taken it back, so the
  /// next tab in line can be granted by the time this returns.
  @override
  Future<void> release() async {
    if (!_request._released.isCompleted) _request._released.complete();
    await _request._done;
  }
}

/// [MonitorChannel] over a `BroadcastChannel`: every tab of the origin that
/// opens the same name hears what the others post, and not what it posts
/// itself.
class BrowserMonitorChannel implements MonitorChannel {
  BrowserMonitorChannel(String name) : _channel = BroadcastChannel(name);

  final BroadcastChannel _channel;

  @override
  void post(String message) => _channel.postMessage(message.toJS);

  @override
  Stream<String> get messages => EventStreamProviders.messageEvent
      .forTarget(_channel)
      .map((event) => event.data)
      .where((data) => data.typeofEquals('string'))
      .map((data) => (data as JSString).toDart);

  @override
  void close() => _channel.close();
}

/// [PageLifecycle] from the document's `visibilitychange` (when the page
/// becomes visible), and the window's `pageshow` and `online`.
class BrowserPageLifecycle implements PageLifecycle {
  BrowserPageLifecycle();

  late final _controller = StreamController<PageEvent>.broadcast(
      onListen: _subscribe, onCancel: _unsubscribe);
  final _subscriptions = <StreamSubscription<Event>>[];

  @override
  Stream<PageEvent> get events => _controller.stream;

  void _subscribe() {
    _subscriptions.addAll([
      // package:web's own provider picks the prefixed `webkitvisibilitychange`
      // on any browser that still exposes `document.webkitHidden`, Chrome
      // among them, and that event is never fired; every current browser
      // fires the standard name.
      const EventStreamProvider<Event>('visibilitychange')
          .forTarget(document)
          .where((_) => document.visibilityState == 'visible')
          .listen((_) => _controller.add(PageEvent.visible)),
      EventStreamProviders.pageShowEvent
          .forTarget(window)
          .listen((_) => _controller.add(PageEvent.pageShow)),
      EventStreamProviders.onlineEvent
          .forTarget(window)
          .listen((_) => _controller.add(PageEvent.online)),
    ]);
  }

  void _unsubscribe() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
