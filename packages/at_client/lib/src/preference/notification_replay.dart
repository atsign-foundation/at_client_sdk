/// Where a monitor's notification replay starts when it connects.
///
/// Set with [AtClientPreference.notificationReplay]. The start is resolved
/// once per notification service, so a reconnect does not move it forward, and
/// a policy changed after the service's first connect is not seen: set the
/// policy before that connect.
///
/// [resume] and [window] carry their start across a restart only when the
/// client's storage does. On in-memory storage [resume] behaves as [connect]
/// on every start, and [window] replays the same window.
///
/// Every policy writes the last-received watermark as notifications arrive;
/// [connect] and [full] never read it.
sealed class NotificationReplay {
  const NotificationReplay();

  /// Replays nothing sent before the service was created. The store is
  /// neither read nor seeded.
  const factory NotificationReplay.connect() = _Connect;

  /// Replays from the last notification the store holds. A store holding none
  /// starts from the service's creation time, seeded into the store.
  const factory NotificationReplay.resume() = _Resume;

  /// Replays from the later of the last notification the store holds and
  /// [within] before now, which defaults to one hour. A store holding none
  /// starts [within] before now. The start is never later than the service's
  /// creation time, so notifications received since then are delivered once:
  /// a short [within] replays from creation, and a negative [within], treated
  /// as zero, does the same.
  const factory NotificationReplay.window([Duration within]) = _Window;

  /// Replays everything the atServer still holds for this atSign, on every
  /// start: the dedupe is in memory and this policy does not read the stored
  /// ids, so each start delivers the whole retained backlog again. The store
  /// is not read, but each receipt still writes the watermark.
  const factory NotificationReplay.full() = _Full;

  /// Calls the callback for this policy. Exhaustive: a new policy is a
  /// compile error at every caller.
  T when<T>({
    required T Function() connect,
    required T Function() resume,
    required T Function(Duration within) window,
    required T Function() full,
  });
}

final class _Connect extends NotificationReplay {
  const _Connect();

  @override
  T when<T>({
    required T Function() connect,
    required T Function() resume,
    required T Function(Duration within) window,
    required T Function() full,
  }) =>
      connect();

  @override
  bool operator ==(Object other) => other is _Connect;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'NotificationReplay.connect()';
}

final class _Resume extends NotificationReplay {
  const _Resume();

  @override
  T when<T>({
    required T Function() connect,
    required T Function() resume,
    required T Function(Duration within) window,
    required T Function() full,
  }) =>
      resume();

  @override
  bool operator ==(Object other) => other is _Resume;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'NotificationReplay.resume()';
}

final class _Window extends NotificationReplay {
  const _Window([this.within = const Duration(hours: 1)]);

  final Duration within;

  @override
  T when<T>({
    required T Function() connect,
    required T Function() resume,
    required T Function(Duration within) window,
    required T Function() full,
  }) =>
      window(within);

  @override
  bool operator ==(Object other) => other is _Window && other.within == within;

  @override
  int get hashCode => Object.hash(3, within);

  @override
  String toString() => 'NotificationReplay.window($within)';
}

final class _Full extends NotificationReplay {
  const _Full();

  @override
  T when<T>({
    required T Function() connect,
    required T Function() resume,
    required T Function(Duration within) window,
    required T Function() full,
  }) =>
      full();

  @override
  bool operator ==(Object other) => other is _Full;

  @override
  int get hashCode => 4;

  @override
  String toString() => 'NotificationReplay.full()';
}
