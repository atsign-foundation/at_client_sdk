import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/aes_crypto_scheme.dart';
import 'package:at_client/src/crypto/key_lookup.dart';
import 'package:at_client/src/crypto/legacy/legacy_crypto_scheme.dart';
import 'package:at_client/src/crypto/rsa_crypto_scheme.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';

class MockAtLookup extends Mock implements AtLookUp {}

class MockAtLookUpImpl extends Mock implements AtLookupImpl {}

class MockAtChops extends Mock implements AtChops {}

class MockAtChopsKeys extends Mock implements AtChopsKeys {}

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockLocalSecondary extends Mock implements LocalSecondary {}

class MockKeyLookup extends Mock implements KeyLookup {}

class MockSchemeRegistry extends Mock implements SchemeRegistry {
  MockSchemeRegistry(AtClient atClient) {
    register('legacy', LegacyCryptoScheme(atClient));
    register('aes', AESScheme(atClient));
    register('rsa', RSAScheme(atClient));
  }
}

class MockScheme extends Mock implements CryptoScheme {}

class FakeScheme extends Fake implements CryptoScheme {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

class MockAtClientImpl extends Mock implements AtClientImpl {}
