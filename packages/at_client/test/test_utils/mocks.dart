import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/key_lookup.dart';
import 'package:at_client/src/crypto/legacy/legacy_crypto_provider.dart';
import 'package:at_commons/at_builders.dart';
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

class MockCryptoRegistry extends Mock implements CryptoRegistry {
  MockCryptoRegistry(AtClient atClient) {
    register(LegacyCryptoProvider(atClient));
  }
}

class MockCryptoProvider extends Mock implements CryptoProvider {}

class FakeCryptoProvider extends Fake implements CryptoProvider {}

class FakeCryptoEncryptRequest extends Fake implements CryptoEncryptRequest {}

class FakeCryptoDecryptRequest extends Fake implements CryptoDecryptRequest {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  @override
  AtClientPreference getPreferences() {
    return AtClientPreference()..namespace = 'wavi';
  }
}

class MockAtClientImpl extends Mock implements AtClientImpl {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}
