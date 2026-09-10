import 'package:at_utils/at_utils.dart';

/// Logs [message] for an error a background path is about to swallow, at
/// `severe` when the error names a defect and otherwise at the level that path
/// normally uses — `warning`, or `info` when [routine].
///
/// A `TypeError` is the defect: a value of the wrong type reaching the call,
/// which is a bug here or in a test double rather than anything the network or
/// the store can produce. Every other error, `StateError` included, is a
/// condition — this codebase raises `StateError` for a store that is not open
/// yet and a service that is not wired yet, both of which pass.
///
/// The defect is still swallowed. Callers run on a background trigger that has
/// nobody to hand an error to, and one escaping into the zone the trigger
/// fired in can take the isolate down; the level is what changes, so a bug
/// reads as a bug instead of sitting among the conditions.
void logSwallowed(AtSignLogger logger, Object error, String message,
    {bool routine = false}) {
  if (error is TypeError) {
    logger.severe('$message [a TypeError here names a defect rather than a '
        'condition the network or the store can produce]');
  } else if (routine) {
    logger.info(message);
  } else {
    logger.warning(message);
  }
}
