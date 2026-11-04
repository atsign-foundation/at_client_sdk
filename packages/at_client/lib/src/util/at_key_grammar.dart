import 'package:at_commons/at_commons.dart' show Regexes;

/// Whether an atKey can carry [namespace]: word characters after the last
/// dot, and before it only the characters an atKey's name may hold.
bool isAtKeyNamespace(String namespace) => _namespace.hasMatch(namespace);

/// Whether [id] has the shape of a key id or an enrollment id: word
/// characters and hyphens. Every id this client mints, every id an atServer
/// mints, and `primary` have it.
bool isIdShaped(String id) => _id.hasMatch(id);

/// Whether an atKey can name [atSign] as its owner or recipient.
bool isAtKeyAtSign(String atSign) => _atSign.hasMatch(atSign);

final RegExp _namespace = RegExp('^(?:(?:${Regexes.charsInEntity}'
    '|${Regexes.allowedEmoji})+\\.)?${Regexes.charsInNamespace}\$');

final RegExp _id = RegExp(r'^[\w-]+$');

final RegExp _atSign =
    RegExp('^${Regexes.ownershipFragmentWithoutNamedGroup}\$');
