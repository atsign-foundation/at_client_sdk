/// A stand-in for a browser's tabs: at_lookup's in-memory lock and channel
/// hub shared by every [Tab], each with a page lifecycle and an inner
/// muxable of its own.
library;

import 'dart:async';

import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

/// The muxable a tab would build for itself: counts and remembers what the
/// wrapper does to it and lets a test play the atServer.
class FakeInnerMuxable extends Fake implements AtLookupMuxable {
  int startCalls = 0;
  int stopCalls = 0;
  int drops = 0;
  bool started = false;

  /// The watermark callback the wrapper handed down, kept to prove it is the
  /// very function the wrapper was started with.
  Future<int?> Function()? heldWatermarkSource;
  int? startedWithWatermark;

  /// Set to make [startNotifications] fail, as an unreachable atServer does.
  Object? startError;

  StreamController<String> _notifications = StreamController<String>();
  StreamController<bool> _up = StreamController<bool>.broadcast();

  @override
  Stream<String> get notifications => _notifications.stream;

  @override
  Stream<bool> get notificationConnectionUp => _up.stream;

  @override
  bool get isNotifying => started;

  @override
  bool get isReconnectingNotifications => false;

  @override
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  }) async {
    startCalls++;
    if (startError != null) throw startError!;
    started = true;
    heldWatermarkSource = getLastNotificationTime;
    startedWithWatermark = await getLastNotificationTime?.call();
    _up.add(true);
  }

  @override
  Future<void> stopNotifications() async {
    stopCalls++;
    started = false;
    if (!_up.isClosed) _up.add(false);
    final n = _notifications;
    final u = _up;
    _notifications = StreamController<String>();
    _up = StreamController<bool>.broadcast();
    unawaited(n.close());
    unawaited(u.close());
  }

  @override
  Future<void> dropConnection() async {
    drops++;
    _up.add(false);
  }

  @override
  Future<void> stop() async {}

  /// The atServer sends a line.
  void deliver(String line) => _notifications.add(line);

  /// The connection came back after a drop.
  void reconnected() => _up.add(true);
}

/// One browser tab's share of the rig.
class Tab {
  Tab(this.rig, {Duration? beaconInterval, Duration? staleAfter, bool? steal})
      : inner = FakeInnerMuxable(),
        lifecycle = InMemoryPageLifecycle() {
    muxable = TabMuxable(
      inner,
      lock: rig.locks,
      channels: (name) => channel = rig.hub.open(name),
      lifecycle: lifecycle,
      name: rig.name,
      beaconInterval: beaconInterval ?? rig.beaconInterval,
      staleAfter: staleAfter ?? rig.staleAfter,
      steal: steal ?? true,
    );
  }

  final TabRig rig;
  final FakeInnerMuxable inner;
  final InMemoryPageLifecycle lifecycle;
  late final TabMuxable muxable;

  /// The channel the tab opened on its last start.
  InMemoryMonitorChannel? channel;

  /// Every line and state the wrapper surfaced, in order.
  final lines = <String>[];
  final ups = <bool>[];

  /// The watermark callback this tab's `Monitor` would pass.
  Future<int?> watermark() async => 42;

  /// Starts as `Monitor` does: subscribes, then starts.
  Future<void> start() async {
    muxable.notificationConnectionUp.listen(ups.add);
    muxable.notifications.listen(lines.add);
    await muxable.startNotifications(getLastNotificationTime: watermark);
  }
}

/// What every tab of one origin shares.
class TabRig {
  TabRig({
    this.name = 'at-monitor:@alice:primary',
    this.beaconInterval = const Duration(seconds: 30),
    this.staleAfter = const Duration(seconds: 60),
  });

  final String name;
  final Duration beaconInterval;
  final Duration staleAfter;
  final locks = InMemoryMonitorLock();
  final hub = InMemoryChannelHub();

  Tab tab() => Tab(this);
}
