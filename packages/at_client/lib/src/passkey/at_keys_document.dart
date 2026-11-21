import 'package:at_auth/at_auth.dart' show AtKeys, apkamPrivateKey;
import 'package:at_commons/atsign.dart';

const _privateAuthenticationRole = 'privateAuthentication';

/// [keys] as a document, without any APKAM private key: the flat field and
/// every typed `privateAuthentication` material. Names [atSign] when [keys]
/// name none.
Map<String, dynamic> atKeysDocument(AtKeys keys, String atSign) {
  keys.atsign ??= Atsign(atSign);
  final json = Map<String, dynamic>.of(keys.toJson())..remove(apkamPrivateKey);
  final enrollments = json['enrollments'];
  if (enrollments is List) {
    json['enrollments'] = [
      for (final e in enrollments)
        {
          ...(e as Map<String, dynamic>),
          'keys': [
            for (final key in e['keys'] as List)
              {
                ...(key as Map<String, dynamic>),
                'material': [
                  for (final m in key['material'] as List)
                    if ((m as Map)['role'] != _privateAuthenticationRole) m
                ]
              }
          ]
        }
    ];
  }
  return json;
}
