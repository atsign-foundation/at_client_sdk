import 'package:at_auth/src/exception/at_auth_exceptions.dart'
    show AtKeysFormatException;
import 'package:at_commons/at_commons.dart';

/// Why an atSign's keys cannot be used to authenticate as it.
enum AtKeysUnusableCause {
  /// The keys source holds nothing for the atSign.
  absent,

  /// The keys source holds something for the atSign that cannot be read.
  unreadable,

  /// The keys were read but hold no authentication keypair this device can
  /// use: none for the enrollment they authenticate as, one under an
  /// algorithm this build cannot sign with, or several enrollments that each
  /// could be the one.
  noAuthenticationKeypair,

  /// The keys record another atSign.
  anotherAtsign,

  /// The keys hold no credential and no enrollment awaiting approval.
  noCredential,

  /// The keys hold nothing but an enrollment awaiting approval.
  pendingEnrollment,
}

/// Keys that cannot be used to authenticate as [atSign]: [cause] says why,
/// and [source] where they were looked for.
///
/// Its message holds no stack trace and quotes no value read from the keys
/// but the atSign they record, an enrollment id or an algorithm name.
class AtKeysUnusableException extends AtException {
  final String atSign;
  final AtKeysUnusableCause cause;

  /// Where the keys were looked for, as `AtKeysIo.describeSource` names it;
  /// null when whoever threw this named none.
  final String? source;

  /// What reading the keys threw, when something did; a [FormatException]
  /// is kept without its source, which was the text read.
  final Object? error;

  /// Keys unusable for [cause], said by [message].
  AtKeysUnusableException(super.message,
      {required this.atSign, required this.cause, this.source, Object? error})
      : error = _withoutSource(error);

  /// [source] holds no keys for [atSign]; [error] is what the read threw.
  AtKeysUnusableException.absent(this.atSign,
      {required String this.source, Object? error})
      : cause = AtKeysUnusableCause.absent,
        error = _withoutSource(error),
        super('No keys for $atSign ${_where(source)}, so this device cannot '
            'authenticate as $atSign. Activate $atSign, enroll this device, '
            'or use the keyfile it already has.');

  /// [source] holds keys for [atSign] that reading them failed on with
  /// [error].
  AtKeysUnusableException.unreadable(this.atSign,
      {required String this.source, required Object error})
      : cause = AtKeysUnusableCause.unreadable,
        error = _withoutSource(error),
        super('The keys for $atSign ${_where(source)} could not be read: '
            '${_reasonFor(error)}.');

  /// The keys in [source] for [atSign] were read, and resolving the keypair
  /// to authenticate with failed with [error].
  AtKeysUnusableException.noAuthenticationKeypair(this.atSign,
      {required String this.source, required Object error})
      : cause = AtKeysUnusableCause.noAuthenticationKeypair,
        error = _withoutSource(error),
        super('The keys for $atSign ${_where(source)} cannot be used to '
            'authenticate: ${_reasonFor(error)}.');

  /// The keys in [source] record [recorded], an atSign other than [atSign].
  AtKeysUnusableException.anotherAtsign(this.atSign, String recorded,
      {required String this.source})
      : cause = AtKeysUnusableCause.anotherAtsign,
        error = null,
        super('The keys ${_where(source)} are for $recorded, not $atSign.');
}

/// [error], or for a [FormatException] carrying the text it failed on, the
/// same exception without that text.
Object? _withoutSource(Object? error) =>
    error is FormatException && error.source != null
        ? FormatException(error.message, null, error.offset)
        : error;

/// [source] with the preposition a message puts before it: `in` before a
/// name, which begins "the" or "this", and `at` before a path.
String _where(String source) =>
    source.startsWith('the ') || source.startsWith('this ')
        ? 'in $source'
        : 'at $source';

/// Why [error] leaves the keys unusable, in one line: what the error says,
/// which names where the keys failed and quotes no value from them
/// but an enrollment id or an algorithm name.
String _reasonFor(Object error) {
  final text = switch (error) {
    AtKeysFormatException(:final isJson, :final reason, :final position) =>
      isJson
          ? 'it is $reason'
          : 'it is not valid JSON: $reason'
              '${position == null ? '' : ' (at character $position)'}',
    // NOTE: a FormatException's text carries its source, which here is what
    // was read; only its message is used.
    FormatException(:final message) => message,
    AtException(:final message) => message,
    _ => '$error',
  };
  final line = text.split('\n').first.trim();
  return line.endsWith('.') ? line.substring(0, line.length - 1) : line;
}
