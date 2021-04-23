import 'dart:convert';
import 'dart:typed_data';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';

class TestUtil {
  static AtClientPreference getPreferenceRemote() {
    var preference = AtClientPreference();
    preference.isLocalStoreRequired = false;
    preference.privateKey = ''; // specify private key of user here.
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    preference.outboundConnectionTimeout = 60000;
    return preference;
  }

  static AtClientPreference getPreferenceLocal() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.commitLogPath = 'hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.syncStrategy = SyncStrategy.IMMEDIATE;
    preference.privateKey = ''; // specify private key of user here.
    preference.rootDomain = 'test.do-sf2.atsign.zone';
    preference.keyStoreSecret =
        _getKeyStoreSecret(''); // path of hive encryption key filefor client
    return preference;
  }

  static AtClientPreference getAlicePreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.commitLogPath = 'hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.syncStrategy = SyncStrategy.IMMEDIATE;
    preference.privateKey =
        'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCDVMetuYSlcwNdS1yLgYE1oBEXaCFZjPq0Lk9w7yjKOqKgPCWnuVVly5+GBkYPYN3mPXbi/LHy3SqVM/8s5srxa+C8s5jk2pQI6BgG/RW59XM6vrGuw0pUQoL0bMyQxtR8XAFVgd54iDcgp4ZPLEH6odAgBraAtkIEpfwSwtMaWJCaS/Yn3q6ZoVOxL+O7DHD2dJWmwwjAJyDqEDeeNVuNHWnmj2ZneVXDnsY4fOR3IZdcGArM28FFcFIM6Q0K6XGiLGvJ2pYPywtzwARFChYJTBJYhNNLRgT+MUvx8fbNa6mMnnXQmagh/YvYwmyIUVQK1EhFNZIgezX9xdmIgS+FAgMBAAECggEAEq0z2FjRrFW23MWi25QHNAEXbSS52WpbHNSZJ45bVqcQCYmEMV4B7wAOJ5kszXMRG3USOyWEiO066Q0D9Pa9VafpxewkiicrdjjLcfL76/4j7O7BhgDvyRvMU8ZFMTGVdjn/VpGpeaqlbFdmmkvI9kOcvXE28wb4TIDuYBykuNI6twRqiaVd1LkKg9yoF0DGfSp8OHGWm/wz5wwnNYT6ofTbgV3gSGKOrLf4rC1swHh1VoNXiaYKQQFo2j23vGznC+hVJy8kAkSTMvRy4+SrZ+0MtYrNt0CI9n4hw79BNzwAd0kfJ5WCsYL6MaF8Giyym3Wl77KoiriwRF7cGCEnAQKBgQDWD+l1b6D8QCmrzxI1iZRoehfdlIlNviTxNks4yaDQ/tu6TC/3ySsRhKvwj7BqFYj2A6ULafeh08MfxpG0MfmJ+aJypC+MJixu/z/OXhQsscnR6avQtVLi9BIZV3EweyaD/yN/PB7IVLuhz6E6BV8kfNDb7UFZzrSSlvm1YzIdvQKBgQCdD5KVbcA88xkv/SrBpJcUME31TIR4DZPg8fSB+IDCnogSwXLxofadezH47Igc1CifLSQp4Rb+8sjVOTIoAXZKvW557fSQk3boR3aZ4CkheDznzjq0vY0qot4llkzHdiogaIUdPDwvYBwERzc73CO3We1pHs36bIz70Z3DRF5BaQKBgQC295jUARs4IVu899yXmEYa2yklAz4tDjajWoYHPwhPO1fysAZcJD3E1oLkttzSgB+2MD1VOTkpwEhLE74cqI6jqZV5qe7eOw7FvTT7npxd64UXAEUUurfjNz11HbGo/8pXDrB3o5qoHwzV7RPg9RByrqETKoMuUSk1FwjPSr9efQKBgAdC7w4Fkvu+aY20cMOfLnT6fsA2l3FNf2bJCPrxWFKnLbdgRkYxrMs/JOJTXT+n93DUj3V4OK3036AsEsuStbti4ra0b7g3eSnoE+2tVXl8q6Qz/rbYhKxR919ZgZc/OVdiPbVKUaYHFYSFHmKgHO6fM8DGcdOALUx/NoIOqSTxAoGBALUdiw8iyI98TFgmbSYjUj5id4MrYKXaR7ndS/SQFOBfJWVH09t5bTxXjKxKsK914/bIqEI71aussf5daOHhC03LdZIQx0ZcCdb2gL8vHNTQoqX75bLRN7J+zBKlwWjjrbhZCMLE/GtAJQNbpJ7jOrVeDwMAF8pK+Put9don44Gx';
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@alice🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('hive/client/' + hashFile + '.hash');
    return preference;
  }

  static AtClientPreference getBobPreference() {
    var preference = AtClientPreference();
    preference.hiveStoragePath = 'hive/client';
    preference.commitLogPath = 'hive/client/commit';
    preference.isLocalStoreRequired = true;
    preference.syncStrategy = SyncStrategy.IMMEDIATE;
    preference.privateKey =
        'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCxGGbUHy3bpdMQdvQn5F5dAMEbcDsaYDYsvqYAkjLKGPwgl5pk8gdxU6HnWLaXJDwZd4xRaUDHYToGD+k1xp2SEFjMsxD4PAA9k/hKtddEpaDHEGiC3kOf3VD12BJ3VyFsikZutZtgwF7o5cJCdU5Ppqno5ThChV5I3ZUelfoumqQF1iKnZ3z/NdtWAyFs7HNcuO+bL7ls28CNpVkrPxHbydLL/Y/qqR9xeJ5wm8WnQr5YRVFgYGNi03NlsW0UODkE3mufXAC8ALnQ3W9iQa/pW3QXwMKzuyebF29Jfsx/ELvfnzbgRdlKPNEI++phQyMrvZ67uhSewQnAUrW8+aTfAgMBAAECggEBAInMtf6qgDFgd7phBRyhWze85YXnL2YXpS/t7ReWqwSMqmrl7FJN7bKl494zLmiu3kDmv/19C9XYdqDO8qVQdb15EM+/Kh4t+fXwVIw1sFqPEmqy/s+OCUq0mFGjnsLTvoNJmQJ+N3fyWCea2CyEQLpDsgQxkDRauIG0QVs6UiC+EWaolgYtDvNrXgybjjQyvbdSV5jxuYHvt8uzjyUVDQy22mq9H2S3ztI7KqZYoikoAq+baP5RHqD0CBd7hlZPjEo8+aeQN1WeXKiNQGO6JTfWQRquiGpQkwaVXt7kYPwQ0tYrpOXOT9kCWot+aTMbgyIkUmP44IoxMcsyBzi+PVECgYEA5ErweSkb+DGBKSDOcWJDhsfS6jLTu8fe1Y7h9TtRR4436GzpEPFQPd4192e96oe/IjibWQiIqm4KIwXPw7clXMhOtFpMu5935cJfzWkSaa+m9lHRmn/ire52J13KZc7eYpYQiSXue2aKVLQhG1VDXePO+N6M9gR5Mz52IokFzukCgYEAxpbB6mEbk3//hLNknZGj/WTFQV3FNG43sIn9KZckdBV+9sczAetKNvjScuX4ceNG7XyCnVCl9qmz0+TAGmWfnGB/u4EHyRc5iNNo3q/DVRhUPHeOpSdQw+VOEMN47HELdqzOrK0q4BbSJlFdsHjL0P/oFDWVeY0sqghBb8/4SIcCgYB5gU1GH1QsoCSPgE+AV317QeWHEvBQlIuMfJTVEfIrtI0bHsRZaSZ9F0T/3e5d4kwfaaN9GqaqlxC8HT68e0DehholsZ3/ilulJPQaft728y9ZEKkPoxtB2ZZ3U1sDHryMGjTI2jB461WayZiJVLMbSMGDAehilHTxikAUF3vI6QKBgQCU7WInXwPLLeZ1ogMGl74fvX6gcq39j9p7rkAI/Kv90lEQyHpcKhPR/e/08rnKzuLWHtXlHCIaRVHyyk22fhegsk2YVD9+cshW8BRpS+501nX1ksOK310WS9SrhawdxPkP2rBzlrncq8CVs9dLDIvtBL0KytR5/4FLUj2gmJpd6QKBgGNLjdysAYCd0GVVe7kKTuBks12jrMWbJqYq35NRTnKt3qYPe8Xuzy5WETDMWtWleIfXpbb+NEIQJ7ifs3dAJZ6/s/jo/tRawS8Hpa6j2oeGFcvCiI9rukd0gXuUDD2d0//RHxyJXpraE+5wx7JhAFm2opZOez98BgRoo0hISwAj';
    preference.rootDomain = 'vip.ve.atsign.zone';
    var hashFile = _getShaForAtSign('@bob🛠');
    preference.keyStoreSecret =
        _getKeyStoreSecret('hive/client/' + hashFile + '.hash');
    return preference;
  }

  static List<int> _getKeyStoreSecret(String filePath) {
    var hiveSecretString = File(filePath).readAsStringSync();
    var secretAsUint8List = Uint8List.fromList(hiveSecretString.codeUnits);
    return secretAsUint8List;
  }

  static String _getShaForAtSign(String atsign) {
    var bytes = utf8.encode(atsign);
    return sha256.convert(bytes).toString();
  }
}
