import 'package:at_utils/at_utils.dart';

/// Logs [message] for an error a background path is about to swallow, at
/// `severe` when the error names a defect and otherwise at the level that path
/// normally uses — `warning`, or `info` when [routine].
///
/// Two errors are defects, and both mean the same thing: a null reached a
/// place that needed a value. A `TypeError` is a value of the wrong type
/// arriving at the call; a `NoSuchMethodError` is a member invoked on a null
/// receiver. Neither is anything the network or the store can produce, so both
/// are a bug here or in a test double.
///
/// Every other error is a condition, `StateError` included — this codebase
/// raises `StateError` for a store that is not open yet and a service that is
/// not wired yet, and both of those pass. That is why the test is on the two
/// named types rather than on `Error`.
///
/// The defect is still swallowed. Callers run on a background trigger that has
/// nobody to hand an error to, and one escaping into the zone the trigger
/// fired in can take the isolate down; the level is what changes, so a bug
/// reads as a bug instead of sitting among the conditions.
void logSwallowed(AtSignLogger logger, Object error, String message,
    {bool routine = false}) {
  if (error is TypeError || error is NoSuchMethodError) {
    logger.severe(
        '$message [a ${error is TypeError ? 'TypeError' : 'NoSuchMethodError'} '
        'here names a defect rather than a condition the network or the store '
        'can produce]');
  } else if (routine) {
    logger.info(message);
  } else {
    logger.warning(message);
  }
}
