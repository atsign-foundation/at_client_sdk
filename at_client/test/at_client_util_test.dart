import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group('A group of update builder tests', () {
    test('test non public key', () {
      var builder = UpdateVerbBuilder()
        ..atKey = (AtKey()..key = 'privatekey:at_pkam_privatekey');
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, 'privatekey:at_pkam_privatekey');
    });

    test('test public key', () {
      var metadata = Metadata()..isPublic = true;
      var builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..key = 'phone'
          ..metadata = metadata
          ..sharedBy = '@alice');
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, 'public:phone@alice');
    });

    test('test key sharedwith another atsign', () {
      var builder = UpdateVerbBuilder()
        ..atKey = (AtKey()
          ..sharedWith = 'bob'
          ..key = 'phone'
          ..sharedBy = '@alice');
      var updateKey = AtClientUtil.buildKey(builder);
      expect(updateKey, '@bob:phone@alice');
    });
  });

  group('A group of get secondary info tests', () {
    test('get secondary url and port', () {
      var url = 'atsign.com:6400';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo[0], 'atsign.com');
      expect(secondaryInfo[1], '6400');
    });

    test('url is null', () {
      String? url;
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });

    test('url is empty', () {
      var url = '';
      var secondaryInfo = AtClientUtil.getSecondaryInfo(url);
      expect(secondaryInfo.length, 0);
    });
  });
}
