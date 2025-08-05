// ignore_for_file: constant_identifier_names
import 'package:at_client/at_client.dart';

class TestConstants {
  static const String PKAM_PRIVATE_KEY = 'pkamPrivateKey';
  static const String PKAM_PUBLIC_KEY = 'pkamPublicKey';
  static const String ENCRYPTION_PRIVATE_KEY = 'encryptionPrivateKey';
  static const String ENCRYPTION_PUBLIC_KEY = 'encryptionPublicKey';
  static const String SELF_ENCRYPTION_KEY = 'selfEncryptionKey';
  static const namespace = 'e2e_test';
  static const oneMinuteMillis = 60 * 1000;
  static final ObjectLifeCycleOptions optionsTtlOneMinute =
      ObjectLifeCycleOptions(timeToLive: Duration(minutes: 1));
}
