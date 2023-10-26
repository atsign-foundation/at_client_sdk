import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockAtLookUp extends Mock implements AtLookupImpl {}

void main() {
  AtLookupImpl mockAtLookUp = MockAtLookUp();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  SecondaryAddress fakeSecondaryAddress =
      SecondaryAddress('fake.secondary.address', 8010);
  String atsign = '@remoteSecondaryTest';
  AtClientPreference atClientPreference = AtClientPreference();

  group('tests to verify functionality of remote secondary', () {
    setUp(() {
      reset(mockSecondaryAddressFinder);
      reset(mockAtLookUp);
      when(() => mockSecondaryAddressFinder.findSecondary(atsign.toLowerCase()))
          .thenAnswer((_) async => fakeSecondaryAddress);
      AtClientManager.getInstance().secondaryAddressFinder =
          mockSecondaryAddressFinder;
    });

    test('test findSecondaryUrl', () async {
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      String? address = await remoteSecondary.findSecondaryUrl();
      expect(address, isNotNull);
      expect(address, fakeSecondaryAddress.toString());
    });

    test('executeVerb using scan', () async {
      String fakeScanData = 'data:["key1:value1","key2:value2"]';
      ScanVerbBuilder scanVerbBuilder = ScanVerbBuilder();
      when(() => mockAtLookUp.executeVerb(scanVerbBuilder))
          .thenAnswer((_) async => fakeScanData);
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;

      String result = await remoteSecondary.executeVerb(scanVerbBuilder);
      expect(result, fakeScanData);
    });

    test('executeVerb throws exception', () async {
      ScanVerbBuilder scanVerbBuilder = ScanVerbBuilder();
      when(() => mockAtLookUp.executeVerb(scanVerbBuilder))
          .thenThrow('exception123');
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;

      expect(() async => await remoteSecondary.executeVerb(scanVerbBuilder),
          throwsA('exception123'));
    });

    test('executeAndParse using llookup', () async {
      String fakeLookupData = 'data:lookup data stub';
      LookupVerbBuilder lookupVerbBuilder = LookupVerbBuilder()
        ..atKey = 'dummy_key'
        ..sharedBy = '@alice';
      when(() => mockAtLookUp.executeVerb(lookupVerbBuilder))
          .thenAnswer((_) async => fakeLookupData);
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;
      String result = await remoteSecondary.executeAndParse(lookupVerbBuilder);
      expect(result, 'lookup data stub');
    });
  });
}
