import 'dart:math';

import 'package:at_chops/at_chops.dart';

class TestUtils {
  static String createRandomString(int length) {
    final String characters =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_';
    return String.fromCharCodes(Iterable.generate(length,
        (index) => characters.codeUnitAt(Random().nextInt(characters.length))));
  }

  static Future<AtChops> getAtChops() async {
    AtEncryptionKeyPair atEncryptionKeyPair =
        AtChopsUtil.generateAtEncryptionKeyPair();
    AtPkamKeyPair atPkamKeyPair = AtChopsUtil.generateAtPkamKeyPair();
    AtChopsKeys atChopsKeys =
        AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair);
    atChopsKeys.selfEncryptionKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);
    atChopsKeys.apkamSymmetricKey =
        AtChopsUtil.generateSymmetricKey(EncryptionKeyType.aes256);

    return AtChopsImpl(atChopsKeys);
  }
}
