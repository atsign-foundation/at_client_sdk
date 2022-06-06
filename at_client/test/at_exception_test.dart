import 'package:at_client/at_client.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockRemoteSecondary extends Mock implements RemoteSecondary {}

class MockAtLookup extends Mock implements AtLookupImpl {}

void main() {
  AtLookupImpl mockAtLookup = MockAtLookup();
  var lookupVerbBuilder = LookupVerbBuilder()
    ..atKey = 'phone.wavi'
    ..sharedBy = '@alice';

  setUp(() {
    reset(mockAtLookup);
    when(() => mockAtLookup.executeVerb(lookupVerbBuilder)).thenAnswer(
        (_) async =>
            throw AtExceptionUtils.get('AT0015', 'Connection timeout'));
  });
  // The AtLookup verb throws exception is stacked by the executeVerb in remote secondary
  test('Test to verify exception gets stacked in remote secondary executeVerb',
      () async {
    RemoteSecondary remoteSecondary =
        RemoteSecondary('@alice', AtClientPreference());
    remoteSecondary.atLookUp = mockAtLookup;
    try {
      await remoteSecondary.executeVerb(lookupVerbBuilder);
    } on AtException catch (e) {
      expect(e.getTraceMessage(),
          'Failed to fetch data caused by\nConnection timeout');
    }
  });
}
