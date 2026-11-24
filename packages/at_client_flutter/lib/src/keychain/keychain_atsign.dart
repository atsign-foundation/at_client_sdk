import 'package:at_auth/at_auth.dart' show AtKeys, AtKeysValidationException;
import 'package:at_commons/at_commons.dart';

/// The Atsign a read of [keys] finds in their metadata once they are stored
/// with no typed key material: the `atsign` entry when there is one, else the
/// legacy `name` one, or null when that value is not a non-empty string.
String? metadataAtSignOf(AtKeys keys) => _naming(
  keys.metadata.containsKey('atsign')
      ? keys.metadata['atsign']
      : keys.metadata['name'],
);

/// The Atsign [keys] name, or null when they name none.
///
/// They can name it in their typed `atsign` field and in their metadata's
/// `atsign` and legacy `name` entries, where a value that is not a non-empty
/// string names none. Every Atsign they name must be the same one, and so
/// must [filedAs], the Atsign they are stored for when given, so that a read
/// finds them under it however they are stored and read back. Otherwise this
/// throws [AtKeysValidationException]. Keys naming none are [filedAs]'s.
///
/// Atsigns are compared in their normalized spelling. Only the keys are
/// looked at, never the keychain, and they are left unchanged: [stampAtSign]
/// records the decision on them.
String? atSignNamedBy(AtKeys keys, {String? filedAs}) {
  final named = <(String, String)>[
    if (keys.atsign?.toString() case final typed?) ('atsign field', typed),
    if (_naming(keys.metadata['atsign']) case final entry?)
      ('metadata atsign entry', entry),
    if (_naming(keys.metadata['name']) case final name?)
      ('metadata name entry', name),
  ];
  for (final (where, atSign) in named.skip(1)) {
    final (firstWhere, first) = named.first;
    if (!_sameAtSign(atSign, first)) {
      throw AtKeysValidationException(
        'The keys name ${quotedForMessage(first)} in their $firstWhere and '
        '${quotedForMessage(atSign)} in their $where, so they were not stored',
      );
    }
  }
  final atSign = named.firstOrNull?.$2;
  if (filedAs != null && atSign != null && !_sameAtSign(atSign, filedAs)) {
    throw AtKeysValidationException(
      'The keys name ${quotedForMessage(atSign)}, so they were not stored '
      'for ${quotedForMessage(filedAs)}',
    );
  }
  return atSign ?? normalizedAtSign(filedAs);
}

/// Records [atSign], which [atSignNamedBy] decided [keys] name, in their
/// `atsign` metadata entry when [metadataAtSignOf] would not otherwise find
/// it there.
void stampAtSign(AtKeys keys, String? atSign) {
  if (atSign != null && metadataAtSignOf(keys) == null) {
    keys.metadata['atsign'] = atSign;
  }
}

/// [atSign] in its normalized spelling, so that two spellings of one atSign
/// match the same entry — callers supply either.
///
/// A value `toAtsign()` rejects is returned as it stands rather than
/// dropped, so a malformed stored entry is still readable and removable.
String? normalizedAtSign(String? atSign) {
  if (atSign == null) return null;
  try {
    return atSign.toAtsign().toString();
  } on InvalidAtSignException {
    return atSign;
  }
}

/// [text], from a caller or a keychain item, quoted and clipped for a
/// message.
String quotedForMessage(String text) => '"${clipForMessage(text, quote: '"')}"';

String? _naming(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

bool _sameAtSign(String a, String b) =>
    normalizedAtSign(a) == normalizedAtSign(b);
