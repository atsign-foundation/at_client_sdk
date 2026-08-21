import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io' show stdout;

/// The line protocol between the driver and the two executables.
///
/// One JSON object per line, prefixed by a verb, on stdout. A line protocol
/// rather than an exit code because the driver has to assert a **specific**
/// error for the cells that are expected to fail, and an exit code cannot
/// carry one — "it failed" would let a cell start failing for a different
/// reason unnoticed (`docs/projects/pq/acceptance.md` 16.5).
///
/// Everything else the executables emit shares stdout with this protocol —
/// at_client's own logging among it, which is why the entrypoint runs it at
/// `severe` — and the verb prefix is what keeps a log line from parsing as a
/// verb. stderr carries only the entrypoint's final exception and stack,
/// written after the FAILED line, so a driver dumping stderr must let the
/// pipe drain first.
enum MatrixVerb {
  /// The receiver is subscribed and the sender may start. The driver waits for
  /// this before spawning the sender: notification streams are broadcast and do
  /// not replay, so a sender that runs first is a sender whose notification
  /// nobody was listening for.
  ready,

  /// The sender finished writing, listing what it wrote.
  sent,

  /// The receiver's verdict, listing what it read back.
  result,

  /// Either side failed. Carries the error's runtime type and message
  /// separately, so the driver can pin the type and match on the text.
  failed,
}

/// Marks a protocol line, so nothing else on stdout can be mistaken for one.
///
/// at_client logs through `AtSignLogger`, which prints to stdout. The
/// executables turn that down, but "turned down" is a claim about levels
/// rather than about the stream — a sentinel makes the channel unambiguous
/// whatever gets logged.
const String matrixPrefix = '##PQM##';

/// Emits one protocol line.
void emit(MatrixVerb verb, Map<String, Object?> body) {
  stdout.writeln('$matrixPrefix ${verb.name.toUpperCase()} '
      '${jsonEncode(body)}');
}

/// Emits [MatrixVerb.failed] for [error], splitting the type from the message.
///
/// The type is what a pin should assert on where the failure is structural (a
/// null cast in a released reader is a `_TypeError` whatever its message says),
/// and the message is what names the cause.
void emitFailure(Object error, StackTrace stackTrace, {String? during}) {
  emit(MatrixVerb.failed, {
    'type': error.runtimeType.toString(),
    'message': error.toString(),
    if (during != null) 'during': during,
    'stack': stackTrace.toString().split('\n').take(6).join('\n'),
  });
}

/// One parsed protocol line.
typedef MatrixLine = ({MatrixVerb verb, Map<String, Object?> body});

/// Parses [line], or null when it is not a protocol line at all.
///
/// Returning null rather than throwing is deliberate: an executable is free to
/// print anything else, and the driver skips what it does not recognise rather
/// than failing a cell over a stray line.
MatrixLine? parseLine(String line) {
  final trimmed = line.trimLeft();
  if (!trimmed.startsWith('$matrixPrefix ')) return null;
  final rest = trimmed.substring(matrixPrefix.length + 1);
  final space = rest.indexOf(' ');
  if (space < 0) return null;
  final verb = MatrixVerb.values
      .where((v) => v.name.toUpperCase() == rest.substring(0, space))
      .firstOrNull;
  if (verb == null) return null;
  try {
    final body = jsonDecode(rest.substring(space + 1));
    if (body is! Map) return null;
    return (verb: verb, body: body.cast<String, Object?>());
  } on FormatException {
    return null;
  }
}
