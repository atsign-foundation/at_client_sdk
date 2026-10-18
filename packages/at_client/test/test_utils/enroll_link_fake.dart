import 'dart:convert';

import 'package:at_auth/at_auth.dart' show publicKeyKidOfBase64;
import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:collection/collection.dart' show DeepCollectionEquality;

/// How a fake atServer answers `enroll:link`.
enum EnrollLinkSupport {
  /// As an atServer that carries `enroll:link`.
  supported,

  /// As an atServer whose grammar has no `link`: the command is refused as a
  /// syntax error.
  unknownToGrammar,

  /// As an atServer whose grammar accepts `link` but whose handler has no arm
  /// for it: an empty `data:` reply, and nothing written.
  noHandler,
}

/// Answers [builder], an `enroll:link`, as [support] says, against the `_apsk`
/// records in [remoteData] and [remoteMetadata] — the same maps every client
/// of the test reads.
///
/// A supported atServer refuses the whole call when any link fails: a key the
/// record does not list, the target's authentication key
/// ([authenticationKeyOf]), a key not spelt in padded standard base64, a link
/// over 16 KiB, a payload naming another enrollment or key, or an `expect`
/// that is not the link stored. Otherwise it stores every link in one write,
/// dropping links for keys the record no longer lists, and replies naming the
/// kids it linked. The approve gate is the atServer's and is not modelled.
String answerEnrollLink(
  EnrollVerbBuilder builder, {
  required String atSign,
  required Map<String, String> remoteData,
  required Map<String, Metadata> remoteMetadata,
  required String? Function(String enrollmentId) authenticationKeyOf,
  EnrollLinkSupport support = EnrollLinkSupport.supported,
}) {
  switch (support) {
    case EnrollLinkSupport.unknownToGrammar:
      throw InvalidSyntaxException('Invalid syntax');
    case EnrollLinkSupport.noHandler:
      return 'data:{}';
    case EnrollLinkSupport.supported:
      break;
  }

  final id = builder.enrollmentId!;
  final key = PqSigningChain.apskUri(atSign, id);
  final value = remoteData[key];
  if (value == null) {
    throw AtEnrollmentException('enroll:link: enrollment $id is not approved');
  }
  final advertised = _advertisedKeys(value);
  final stored = _linksIn(remoteMetadata[key]?.appMetadata);
  final authentication = authenticationKeyOf(id);

  final written = <String, Object?>{};
  for (final request in builder.links!.entries) {
    final kid = request.key;
    final listed = advertised[kid];
    if (listed == null ||
        (authentication != null && _sameKey(listed.pub, authentication))) {
      throw IllegalArgumentException('enroll:link: $id advertises no key $kid '
          'that can take a link; an authentication key takes none');
    }
    if (!_isCanonical(listed.pub)) {
      throw IllegalArgumentException('enroll:link: the key $kid is not spelt '
          'in padded standard base64, so it takes no link');
    }
    final body = request.value as Map;
    final link = body['link'];
    if (utf8.encode(jsonEncode(link)).length > 16 * 1024) {
      throw IllegalArgumentException(
          'enroll:link: the link for $kid is over 16384 bytes encoded');
    }
    final payload = _payloadOf(link);
    if (payload == null ||
        payload['enrollmentId'] != id ||
        payload['kid'] != kid ||
        payload['alg'] != listed.alg ||
        payload['pub'] != listed.pub) {
      throw IllegalArgumentException('enroll:link: the link for $kid does not '
          'name enrollment $id and that key');
    }
    if (!const DeepCollectionEquality().equals(body['expect'], stored[kid])) {
      throw IllegalStateException('enroll:link: the link stored for $kid is '
          'not the one this request expects; read it again');
    }
    written[kid] = link;
  }

  final metadata = remoteMetadata[key] ?? Metadata();
  final links = {
    for (final entry in stored.entries)
      if (advertised.containsKey(entry.key)) entry.key: entry.value,
    ...written,
  };
  metadata.appMetadata = AppMetadata(
    providerId: metadata.appMetadata?.providerId ?? 'legacy',
    additional: {
      ...?metadata.appMetadata?.additional,
      PqSigningChain.linksField: links,
    },
  );
  remoteMetadata[key] = metadata;
  return 'data:${jsonEncode({
        'enrollmentId': id,
        'linked': written.keys.toList()
      })}';
}

/// The keys an `_apsk` value lists, by kid, as the atServer reads them: each
/// list entry with a string kid, alg and pub, the first of a repeated kid
/// winning; a bare value is one `rsa2048` key.
Map<String, ({String alg, String pub})> _advertisedKeys(String value) {
  if (!value.trimLeft().startsWith('{')) {
    try {
      return {publicKeyKidOfBase64(value): (alg: 'rsa2048', pub: value)};
    } on FormatException {
      return const {};
    }
  }
  final decoded = jsonDecode(value);
  final entries = decoded is Map ? decoded['keys'] : null;
  if (entries is! List) return const {};
  final keys = <String, ({String alg, String pub})>{};
  for (final entry in entries) {
    if (entry is! Map) continue;
    final kid = entry['kid'], alg = entry['alg'], pub = entry['pub'];
    if (kid is! String || alg is! String || pub is! String) continue;
    keys.putIfAbsent(kid, () => (alg: alg, pub: pub));
  }
  return keys;
}

Map<String, Object?> _linksIn(AppMetadata? appMetadata) {
  final links = appMetadata?.additional?[PqSigningChain.linksField];
  return links is Map ? Map<String, Object?>.from(links) : {};
}

Map<String, Object?>? _payloadOf(Object? link) {
  if (link is! Map) return null;
  final payload = link['payload'];
  if (payload is Map) return Map<String, Object?>.from(payload);
  if (payload is! String) return null;
  try {
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload))));
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

bool _isCanonical(String pub) {
  try {
    return pub.isNotEmpty && base64Encode(base64Decode(pub)) == pub;
  } on FormatException {
    return false;
  }
}

bool _sameKey(String a, String b) {
  try {
    return const DeepCollectionEquality()
        .equals(base64Decode(a.trim()), base64Decode(b.trim()));
  } on FormatException {
    return a.trim() == b.trim();
  }
}
