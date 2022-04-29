import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockSecondaryAddressFinder extends Mock
    implements SecondaryAddressFinder {}

class MockAtLookUp extends Mock implements AtLookupImpl {}

class MockInternetConnectionChecker extends Mock
    implements InternetConnectionChecker {}

void main() {
  AtLookupImpl mockAtLookUp = MockAtLookUp();
  SecondaryAddressFinder mockSecondaryAddressFinder =
      MockSecondaryAddressFinder();
  InternetConnectionChecker mockInternetConnectionChecker =
      MockInternetConnectionChecker();
  SecondaryAddress fakeSecondaryAddress =
      SecondaryAddress('fake.secondary.address', 8010);
  String fakePrivateKey =
      'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCDVMetuYSlcwNdS1yLgYE1oBEXaCFZjPq0Lk9w7yjKOqKgPCWnuVVly5+GBkYPYN3mPXbi/LHy3SqVM/8s5srxa+C8s5jk2pQI6BgG/RW59XM6vrGuw0pUQoL0bMyQxtR8XAFVgd54iDcgp4ZPLEH6odAgBraAtkIEpfwSwtMaWJCaS/Yn3q6ZoVOxL+O7DHD2dJWmwwjAJyDqEDeeNVuNHWnmj2ZneVXDnsY4fOR3IZdcGArM28FFcFIM6Q0K6XGiLGvJ2pYPywtzwARFChYJTBJYhNNLRgT+MUvx8fbNa6mMnnXQmagh/YvYwmyIUVQK1EhFNZIgezX9xdmIgS+FAgMBAAECggEAEq0z2FjRrFW23MWi25QHNAEXbSS52WpbHNSZJ45bVqcQCYmEMV4B7wAOJ5kszXMRG3USOyWEiO066Q0D9Pa9VafpxewkiicrdjjLcfL76/4j7O7BhgDvyRvMU8ZFMTGVdjn/VpGpeaqlbFdmmkvI9kOcvXE28wb4TIDuYBykuNI6twRqiaVd1LkKg9yoF0DGfSp8OHGWm/wz5wwnNYT6ofTbgV3gSGKOrLf4rC1swHh1VoNXiaYKQQFo2j23vGznC+hVJy8kAkSTMvRy4+SrZ+0MtYrNt0CI9n4hw79BNzwAd0kfJ5WCsYL6MaF8Giyym3Wl77KoiriwRF7cGCEnAQKBgQDWD+l1b6D8QCmrzxI1iZRoehfdlIlNviTxNks4yaDQ/tu6TC/3ySsRhKvwj7BqFYj2A6ULafeh08MfxpG0MfmJ+aJypC+MJixu/z/OXhQsscnR6avQtVLi9BIZV3EweyaD/yN/PB7IVLuhz6E6BV8kfNDb7UFZzrSSlvm1YzIdvQKBgQCdD5KVbcA88xkv/SrBpJcUME31TIR4DZPg8fSB+IDCnogSwXLxofadezH47Igc1CifLSQp4Rb+8sjVOTIoAXZKvW557fSQk3boR3aZ4CkheDznzjq0vY0qot4llkzHdiogaIUdPDwvYBwERzc73CO3We1pHs36bIz70Z3DRF5BaQKBgQC295jUARs4IVu899yXmEYa2yklAz4tDjajWoYHPwhPO1fysAZcJD3E1oLkttzSgB+2MD1VOTkpwEhLE74cqI6jqZV5qe7eOw7FvTT7npxd64UXAEUUurfjNz11HbGo/8pXDrB3o5qoHwzV7RPg9RByrqETKoMuUSk1FwjPSr9efQKBgAdC7w4Fkvu+aY20cMOfLnT6fsA2l3FNf2bJCPrxWFKnLbdgRkYxrMs/JOJTXT+n93DUj3V4OK3036AsEsuStbti4ra0b7g3eSnoE+2tVXl8q6Qz/rbYhKxR919ZgZc/OVdiPbVKUaYHFYSFHmKgHO6fM8DGcdOALUx/NoIOqSTxAoGBALUdiw8iyI98TFgmbSYjUj5id4MrYKXaR7ndS/SQFOBfJWVH09t5bTxXjKxKsK914/bIqEI71aussf5daOHhC03LdZIQx0ZcCdb2gL8vHNTQoqX75bLRN7J+zBKlwWjjrbhZCMLE/GtAJQNbpJ7jOrVeDwMAF8pK+Put9don44Gx';
  String atsign = '@remoteSecondaryTest';
  AtClientPreference atClientPreference = AtClientPreference();
  atClientPreference.privateKey = fakePrivateKey;

  group('tests to verify functionality of remote secondary', () {
    setUp(() {
      reset(mockSecondaryAddressFinder);
      reset(mockAtLookUp);
      reset(mockInternetConnectionChecker);
      when(() => mockSecondaryAddressFinder.findSecondary(atsign))
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
      LookupVerbBuilder lookupVerbBuilder = LookupVerbBuilder();
      when(() => mockAtLookUp.executeVerb(lookupVerbBuilder))
          .thenAnswer((_) async => fakeLookupData);
      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      remoteSecondary.atLookUp = mockAtLookUp;
      String result = await remoteSecondary.executeAndParse(lookupVerbBuilder);
      expect(result, 'lookup data stub');
    });

    test('test isAvailable', () async {
      InternetAddress internetAddress =
          InternetAddress('1.2.3.4', type: InternetAddressType.IPv4);
      AddressCheckOptions fakeAddressCheckOptions =
          AddressCheckOptions(internetAddress, port: fakeSecondaryAddress.port);
      List<InternetAddress> fakeInternetAddressList = [internetAddress];
      when(() => InternetAddress.lookup(fakeSecondaryAddress.host)) //tried any().lookup() which was returning a noSuchMethod error
          .thenAnswer((_) async => fakeInternetAddressList);
      when(() => mockInternetConnectionChecker
              .isHostReachable(fakeAddressCheckOptions))
          .thenAnswer(
              (_) async => AddressCheckResult(fakeAddressCheckOptions, true));

      RemoteSecondary remoteSecondary =
          RemoteSecondary(atsign, atClientPreference);
      bool result = await remoteSecondary.isAvailable();
      expect(result, true);
    });
  });
}
