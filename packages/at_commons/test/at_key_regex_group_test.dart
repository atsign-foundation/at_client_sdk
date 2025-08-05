import 'dart:collection';

import 'package:test/test.dart';

void main() {
  group('Public or private key regex match tests', () {
    test('Valid groups in public keys', () {
      var regex =
          r'(?<visibility>(public|private){1}:)((@(?<sharedWith>([\w\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]))){1,55}):))?(?<entity>([\w\.\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])))+)\.(?<namespace>([\w])+)@(?<owner>([\w\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]))){1,55})';
      var regExp = RegExp(regex, caseSensitive: false);

      // 1. public key with sharedWith specified
      var matches = regExp.allMatches('public:@jagannadh:phone.buzz@jagannadh');
      expect(matches.isNotEmpty, true);
      var verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagannadh');
      expect(verbParams['entity'], 'phone');
      expect(verbParams['owner'], 'jagannadh');
      expect(verbParams['namespace'], 'buzz');

      // 2. public key with sharedWith not specified
      matches = regExp.allMatches('public:phone.buzz@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['entity'], 'phone');
      expect(verbParams['owner'], 'jagannadh');
      expect(verbParams['namespace'], 'buzz');

      // 3. public key with sharedWith specified and single character entity and namespace
      matches = regExp.allMatches('public:@jagannadh:p.b@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagannadh');
      expect(verbParams['entity'], 'p');
      expect(verbParams['owner'], 'jagannadh');
      expect(verbParams['namespace'], 'b');

      // 4. public key with single character entity and namespace
      matches = regExp.allMatches('public:p.b@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['entity'], 'p');
      expect(verbParams['namespace'], 'b');
      expect(verbParams['owner'], 'jagannadh');

      // 5. public key with punctuations in the entity name
      matches = regExp.allMatches('public:pho_-ne.b@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['entity'], 'pho_-ne');
      expect(verbParams['namespace'], 'b');
      expect(verbParams['owner'], 'jagannadh');

      // 6. public key with many punctuations in the entity name
      matches = regExp.allMatches('public:pho_-n________e.b@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['entity'], 'pho_-n________e');
      expect(verbParams['namespace'], 'b');
      expect(verbParams['owner'], 'jagannadh');

      // 7. public key with max of 55 characters for the @sign
      matches = regExp.allMatches(
          'public:@jagannadh0123456789012345678901234567890123456789012345:phone.buzz@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'],
          'jagannadh0123456789012345678901234567890123456789012345');
      expect(verbParams['entity'], 'phone');
      expect(verbParams['namespace'], 'buzz');
      expect(verbParams['owner'], 'jagannadh');

      // 8. public key with valid punctuations in the @sign
      matches =
          regExp.allMatches('public:@jagann_a-d_h:phone.buzz@jagann_a-d_h');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagann_a-d_h');
      expect(verbParams['entity'], 'phone');
      expect(verbParams['namespace'], 'buzz');
      expect(verbParams['owner'], 'jagann_a-d_h');

      // 9. public key with emoji's in @sign
      matches = regExp.allMatches('public:@jagannadh💙:phone.buzz@jagannadh💙');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagannadh💙');
      expect(verbParams['entity'], 'phone');
      expect(verbParams['namespace'], 'buzz');
      expect(verbParams['owner'], 'jagannadh💙');

      // 10. public key with emoji's in entity
      matches = regExp.allMatches('public:@jagannadh:phone😀.buzz@jagannadh');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagannadh');
      expect(verbParams['entity'], 'phone😀');
      expect(verbParams['namespace'], 'buzz');
      expect(verbParams['owner'], 'jagannadh');

      // 11. Emojis in both @sign and entity
      matches =
          regExp.allMatches('public:@jagannadh💙:phone😀.buzz@jagannadh💙');
      expect(matches.isNotEmpty, true);
      verbParams = _getVerbParams(matches);
      expect(verbParams['visibility'], 'public:');
      expect(verbParams['sharedWith'], 'jagannadh💙');
      expect(verbParams['entity'], 'phone😀');
      expect(verbParams['namespace'], 'buzz');
      expect(verbParams['owner'], 'jagannadh💙');
      // TO DO: Add and test ' and "
    });

    test('Valid groups in invalid public keys', () {
      var regex =
          r'(?<visibility>(public:|private:){1})((@(?<sharedWith>([\w\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]))){1,55}):))?(?<entity>([\w\.\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])))+)\.(?<namespace>([\w])+)@(?<owner>([\w\-_]|((\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]))){1,55})';
      var regExp = RegExp(regex, caseSensitive: false);
      // 1. Misspelt public
      expect(
          regExp
              .allMatches('publicc:@jagannadh:phone.buzz@jagannadh')
              .isNotEmpty,
          false);
      // 2. No public
      expect(regExp.allMatches('phone.buzz@jagannadh').isNotEmpty, false);
      // 3. No namespace
      expect(regExp.allMatches('public:@jagannadh:phone@jagannadh').isNotEmpty,
          false);
      // 4. No public and start with a :
      expect(regExp.allMatches(':phone.buzz@jagannadh').isNotEmpty, false);
      // 5. Invalid punctuations in the entity name
      expect(regExp.allMatches('public:pho#ne.b@jagannadh').isNotEmpty, false);
      // 6. Valid and invalid punctuations together
      expect(regExp.allMatches('public:pho#n____-____e.b@jagannadh').isNotEmpty,
          false);
      // 7. More than 55 characters for the @sign
      expect(
          regExp
              .allMatches(
                  'public:@jagannadh0123456789012345678901234567890123456789012345extra:phone.buzz@jagannadh')
              .isNotEmpty,
          false);
      // 8. Invalid punctuations in the @sign
      expect(
          regExp
              .allMatches('public:@jaganna#dh:phone.buzz@jagannadh')
              .isNotEmpty,
          false);
      // 9. Invalid and valid punctuations in the @sign
      expect(
          regExp
              .allMatches("public:@jagan_____na#dh💙:phone.buzz@jagannadh💙")
              .isNotEmpty,
          false);
    });
  });
}

HashMap<String, String?> _getVerbParams(Iterable<RegExpMatch> matches) {
  var paramsMap = HashMap<String, String?>();
  for (var f in matches) {
    for (var name in f.groupNames) {
      paramsMap.putIfAbsent(name, () => f.namedGroup(name));
    }
  }
  return paramsMap;
}
