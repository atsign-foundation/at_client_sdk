import 'package:at_client/at_client.dart';
import 'package:location_sharing/models/location_share.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  group('LocationPoint', () {
    test('round-trips through JSON, including accuracy', () {
      final point = LocationPoint(
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 12.5,
      );

      final restored = LocationPoint.fromJson(point.toJson());

      expect(restored.latitude, point.latitude);
      expect(restored.longitude, point.longitude);
      expect(restored.accuracyMeters, point.accuracyMeters);
    });

    test('omits accuracyMeters from JSON when absent', () {
      final point = LocationPoint(latitude: 1, longitude: 2);

      expect(point.toJson().containsKey('accuracyMeters'), isFalse);
      expect(LocationPoint.fromJson(point.toJson()).accuracyMeters, isNull);
    });
  });

  group('LocationShare', () {
    test('round-trips through JSON with a point and a status', () {
      final share = LocationShare(
        status: LocationShareStatus.paused,
        latestPoint: LocationPoint(latitude: 1, longitude: 2),
        updatedAt: DateTime.utc(2026, 1, 1, 12),
      );

      final restored = LocationShare.fromJson(share.toJson());

      expect(restored.status, LocationShareStatus.paused);
      expect(restored.latestPoint?.latitude, 1);
      expect(restored.updatedAt, DateTime.utc(2026, 1, 1, 12));
    });

    test('round-trips with no point yet', () {
      final share = LocationShare(
        status: LocationShareStatus.active,
        latestPoint: null,
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final restored = LocationShare.fromJson(share.toJson());

      expect(restored.latestPoint, isNull);
      expect(restored.status, LocationShareStatus.active);
    });

    test('defaults status to active when missing from JSON', () {
      final restored = LocationShare.fromJson({
        'updatedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      });

      expect(restored.status, LocationShareStatus.active);
    });
  });

  group(r'$LocationShare path fields', () {
    late MockAtClient atClient;
    late AtCollection<LocationShare> collection;
    final selfAtSign = '@alice'.toAtsign();

    setUp(() {
      clearFactoriesForTest();
      atClient = MockAtClient();
      when(() => atClient.atSign).thenReturn(selfAtSign);
      collection = collectionWithInjectedNotifications<LocationShare>(
        atClient,
        'shares.location_sharing',
        const Duration(hours: 1),
        notifications: const Stream<AtNotification>.empty(),
        fromJson: LocationShare.fromJson,
        typeTag: 'LocationShare',
      );
    });

    test('status extracts the share status', () {
      final item = collection.draft(
        obj: LocationShare(
          status: LocationShareStatus.paused,
          latestPoint: null,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      expect($LocationShare.status.extract(item), LocationShareStatus.paused);
    });

    test('updatedAt extracts the last-updated timestamp', () {
      final updatedAt = DateTime.utc(2026, 2, 3, 4);
      final item = collection.draft(
        obj: LocationShare(
          status: LocationShareStatus.active,
          latestPoint: null,
          updatedAt: updatedAt,
        ),
      );

      expect($LocationShare.updatedAt.extract(item), updatedAt);
    });
  });
}
