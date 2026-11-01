/// Drives one publish at a time from a periodic caller (e.g. a `Timer`),
/// so a slow publish can never be overtaken by a later, faster one.
///
/// A `Timer.periodic` callback that awaits an async publish without
/// serialising is a race: if a tick's publish is still in flight when the
/// next tick fires, the two run concurrently and whichever finishes last
/// wins, even if it started first. [tick] closes that window by skipping a
/// tick outright whenever the previous one hasn't finished yet, so publishes
/// for a given [SerializedPeriodicPublisher] are always strictly ordered.
///
/// ```dart
/// final publisher = SerializedPeriodicPublisher<LocationPoint>(
///   fetch: locationProvider.call,
///   publish: service.publishCurrentLocation,
/// );
/// Timer.periodic(const Duration(seconds: 5), (_) => publisher.tick());
/// ```
class SerializedPeriodicPublisher<T> {
  SerializedPeriodicPublisher({required this.fetch, required this.publish});

  /// Fetches the next value to publish, or `null` if none is available yet.
  final Future<T?> Function() fetch;

  /// Publishes [value]. Not called while a previous [tick] is still
  /// fetching or publishing.
  final Future<void> Function(T value) publish;

  bool _isPublishing = false;

  /// Call this on every timer tick. No-ops immediately if a previous
  /// [tick] call hasn't finished yet.
  Future<void> tick() async {
    if (_isPublishing) return;
    _isPublishing = true;
    try {
      final value = await fetch();
      if (value != null) await publish(value);
    } finally {
      _isPublishing = false;
    }
  }
}
