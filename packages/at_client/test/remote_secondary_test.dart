import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';
import 'test_utils/mocks.dart';

/// Captures the command sent via [sendSync].
class _CapturingCommandExecutor implements AtCommandExecutor {
  String? lastCommand;

  @override
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis}) async {
    lastCommand = command;
    return '';
  }
}

void main() {
  AtLookupImpl mockAtLookUp = MockAtLookUpImpl();
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

    test(
        'the lookup it builds is a muxable carrying an authenticator, not a '
        'lookup with credentials parked on it', () async {
      final preference = AtClientPreference()..privateKey = 'dummy_private_key';
      final remoteSecondary = RemoteSecondary(atsign, preference);

      expect(remoteSecondary.atLookUp, isA<AtLookupMuxable>(),
          reason: 'withSecureSocket returns the muxable, which is the only '
              'shape that carries an authenticator at all');
      expect((remoteSecondary.atLookUp as AtLookupMuxable).authenticator,
          isNotNull,
          reason: 'credentials travel as an authenticator now; leaving this '
              'null puts authentication back on the deprecated ladder, which '
              'still works and so hides the regression from every live pack');
    });

    test('an injected lookup that is not a muxable is left alone', () async {
      final remoteSecondary =
          RemoteSecondary(atsign, atClientPreference, atLookUp: mockAtLookUp);

      expect(remoteSecondary.atLookUp, same(mockAtLookUp),
          reason: 'the caller supplied it, so it is used as given');
    });

    test(
        'the installed authenticator still carries clientConfig, so the '
        'from: command it sends keeps naming this client to the atServer',
        () async {
      final preference = AtClientPreference()
        ..privateKey = 'dummy_private_key'
        ..atClientParticulars.appName = 'remote_secondary_test_app';
      final remoteSecondary = RemoteSecondary(atsign, preference);
      final authenticator =
          (remoteSecondary.atLookUp as AtLookupMuxable).authenticator;
      expect(authenticator, isNotNull);

      final capturingExecutor = _CapturingCommandExecutor();
      await authenticator!(capturingExecutor);

      expect(capturingExecutor.lastCommand, contains(':clientConfig:'),
          reason: '_installAuthenticator builds authenticatorForPrivateKey '
              'without threading _getClientConfig() through, so the from: '
              'command it sends drops the client version/id/appName the '
              'atServer used to receive from every authenticated connection');
      expect(
          capturingExecutor.lastCommand, contains('remote_secondary_test_app'));
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
        ..atKey = (AtKey()
          ..key = 'dummy_key'
          ..sharedBy = '@alice');
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
