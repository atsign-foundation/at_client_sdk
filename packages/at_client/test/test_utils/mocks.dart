import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
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

class MockCryptoProvider extends Mock implements CryptoProvider {}

class FakeCryptoProvider extends Fake implements CryptoProvider {}

class MockAtClientManager extends Mock implements AtClientManager {}

class MockAtClient extends Mock implements AtClient {
  // A stable, mutable preference (matching the real getPreferences(), which
  // returns the live instance) so tests can set `.crypto` to inject a
  // CryptoConfig that CryptoRuntime resolves against.
  final AtClientPreference _preference = AtClientPreference()
    ..namespace = 'wavi';

  @override
  AtClientPreference getPreferences() => _preference;
}

class MockAtClientImpl extends Mock implements AtClientImpl {}

class FakeLookupVerbBuilder extends Fake implements LookupVerbBuilder {}
