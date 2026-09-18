import 'dart:async';

final Object _abandonmentZoneKey = Object();

/// Ends the work an owner no longer wants, including sockets still being
/// opened on its behalf.
///
/// Carried as a zone value, so a socket opened anywhere inside [run] belongs
/// to it, even one opened by code that knows nothing of its owner, such as a
/// shared atDirectory finder. Platform-neutral by itself: the socket it ends
/// is [connectTls]'s concern, in `lib/src/io/tls_connect.dart`.
class Abandonment {
  final Set<void Function()> _callbacks = {};
  bool _abandoned = false;

  /// Whether [abandon] has been called.
  bool get isAbandoned => _abandoned;

  /// Runs [callback] once [abandon] is called, or at once if it has been, and
  /// returns what unregisters it.
  void Function() onAbandon(void Function() callback) {
    if (_abandoned) {
      callback();
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  /// Runs every registered callback; later calls do nothing.
  void abandon() {
    if (_abandoned) return;
    _abandoned = true;
    final callbacks = List.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  /// Runs [body] inside this abandonment.
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_abandonmentZoneKey: this});

  /// The abandonment the current code runs inside, if any.
  static Abandonment? get current =>
      Zone.current[_abandonmentZoneKey] as Abandonment?;
}
