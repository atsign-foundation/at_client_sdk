import 'package:at_commons/src/exception/at_exceptions.dart' show AtException;

/// Thrown by work whose owner has stopped: an operation of an `AtClient`
/// that has been stopped, or any call on an at_lookup connection its owner
/// has closed.
///
/// Not an [AtException], so a catch that chooses a fallback for an ordinary
/// failure does not read a stop as one of them.
class StoppedException implements Exception {
  /// What had stopped, and what could not be done because of it.
  final String message;

  StoppedException(this.message);

  @override
  String toString() => 'StoppedException: $message';
}
