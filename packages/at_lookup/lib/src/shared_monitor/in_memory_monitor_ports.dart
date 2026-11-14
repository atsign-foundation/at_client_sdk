/// The shared-monitor ports in memory: what a browser gives every tab of an
/// origin, for the tabs of one isolate.
///
/// For tests, and for running the shared monitor where there is no browser.
/// A lock manager and a channel hub are shared by the `TabMuxable`s that are
/// to coordinate; each gets a lifecycle of its own.
library;

import 'dart:async';

import 'shared_monitor_ports.dart';

/// `navigator.locks` in memory: grants in request order, one holder per
/// name, `steal` preempting both the holder and the queue.
class InMemoryMonitorLock implements MonitorLock {
  final _queues = <String, List<_Request>>{};
  final _holders = <String, _Grant>{};

  /// How many requests were made, aborted while waiting, and made with
  /// `steal`.
  int requests = 0;
  int aborted = 0;
  int steals = 0;

  /// How many requests wait for [name].
  int queued(String name) => _queues[name]?.length ?? 0;

  bool isHeld(String name) => _holders.containsKey(name);

  @override
  LockRequest request(String name, {bool steal = false}) {
    requests++;
    final request = _Request(name, this);
    if (steal) {
      steals++;
      _holders.remove(name)?._lost.complete();
      _grant(request);
    } else {
      (_queues[name] ??= []).add(request);
      _pump(name);
    }
    return request;
  }

  void _pump(String name) {
    if (_holders.containsKey(name)) return;
    final queue = _queues[name];
    if (queue == null || queue.isEmpty) return;
    _grant(queue.removeAt(0));
  }

  void _grant(_Request request) {
    final grant = _Grant(request.name, this);
    _holders[request.name] = grant;
    request._granted.complete(grant);
  }

  void _abort(_Request request) {
    if (_queues[request.name]?.remove(request) != true) return;
    aborted++;
    request._granted.completeError(LockRequestAborted(request.name));
  }

  void _release(_Grant grant) {
    if (!identical(_holders[grant.name], grant)) return;
    _holders.remove(grant.name);
    _pump(grant.name);
  }
}

class _Request implements LockRequest {
  _Request(this.name, this._manager);

  final String name;
  final InMemoryMonitorLock _manager;
  final _granted = Completer<LockGrant>();

  @override
  Future<LockGrant> get granted => _granted.future;

  @override
  void abort() => _manager._abort(this);
}

class _Grant implements LockGrant {
  _Grant(this.name, this._manager);

  final String name;
  final InMemoryMonitorLock _manager;
  final _lost = Completer<void>();

  @override
  Future<void> get lost => _lost.future;

  @override
  Future<void> release() async => _manager._release(this);
}

/// `BroadcastChannel` in memory: a post reaches every other open channel of
/// the same name, delivered asynchronously, never the poster.
class InMemoryChannelHub {
  final _channels = <String, List<InMemoryMonitorChannel>>{};

  /// Every message posted on any channel, oldest first, decoded.
  final posted = <(String name, MonitorMessage message)>[];

  /// A [MonitorChannelFactory] over this hub.
  InMemoryMonitorChannel open(String name) {
    final channel = InMemoryMonitorChannel._(name, this);
    (_channels[name] ??= []).add(channel);
    return channel;
  }

  void _post(InMemoryMonitorChannel from, String message) {
    final decoded = MonitorMessage.decode(message);
    if (decoded != null) posted.add((from.name, decoded));
    for (final channel
        in _channels[from.name] ?? const <InMemoryMonitorChannel>[]) {
      if (identical(channel, from)) continue;
      channel._receive(message);
    }
  }

  void _close(InMemoryMonitorChannel channel) =>
      _channels[channel.name]?.remove(channel);
}

/// One end of an [InMemoryChannelHub].
class InMemoryMonitorChannel implements MonitorChannel {
  InMemoryMonitorChannel._(this.name, this._hub);

  final String name;
  final InMemoryChannelHub _hub;
  final _controller = StreamController<String>.broadcast();
  final _held = <String>[];

  /// A suspended channel neither posts nor hears, as a tab the browser has
  /// frozen does; what it would have heard is delivered when it [resume]s,
  /// as the browser delivers a suspended page's events when it thaws.
  bool suspended = false;

  void resume() {
    suspended = false;
    _held.forEach(_controller.add);
    _held.clear();
  }

  void _receive(String message) {
    if (_controller.isClosed) return;
    if (suspended) {
      _held.add(message);
    } else {
      _controller.add(message);
    }
  }

  @override
  void post(String message) {
    if (suspended) return;
    _hub._post(this, message);
  }

  @override
  Stream<String> get messages => _controller.stream;

  @override
  void close() {
    _hub._close(this);
    _controller.close();
  }
}

/// A page lifecycle whose events a test raises.
class InMemoryPageLifecycle implements PageLifecycle {
  final _controller = StreamController<PageEvent>.broadcast();

  void emit(PageEvent event) => _controller.add(event);

  @override
  Stream<PageEvent> get events => _controller.stream;
}
