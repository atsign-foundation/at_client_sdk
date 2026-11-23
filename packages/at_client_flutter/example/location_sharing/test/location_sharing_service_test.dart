import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:location_sharing/models/location_share.dart';
import 'package:location_sharing/services/location_sharing_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAtClient extends Mock implements AtClient {}

class FakeAtKey extends Fake implements AtKey {}

void main() {
  setUpAll(() => registerFallbackValue(FakeAtKey()));

  late MockAtClient atClient;
  late StreamController<AtNotification> notifStream;
  late LocationSharingService service;

  const namespace = 'shares.location_sharing';
  const selfAtSignStr = '@alice';
  final self = selfAtSignStr.toAtsign();
  const bobStr = '@bob';
  final bob = bobStr.toAtsign();

  setUp(() {
    clearFactoriesForTest();
    atClient = MockAtClient();
    notifStream = StreamController<AtNotification>.broadcast();
    when(() => atClient.atSign).thenReturn(self);
    // No self-key yet: every create()/startSharingWith() call in this file
    // is treated as a brand-new item, matching a fresh demo run.
    when(() => atClient.get(any())).thenThrow(Exception('no such key'));
    when(
      () => atClient.getAtKeys(regex: any(named: 'regex')),
    ).thenAnswer((_) async => <AtKey>[]);
    when(() => atClient.put(any(), any())).thenAnswer((_) async => true);
    when(() => atClient.delete(any())).thenAnswer((_) async => true);

    final shares = collectionWithInjectedNotifications<LocationShare>(
      atClient,
      namespace,
      LocationSharingService.defaultExpiration,
      notifications: notifStream.stream,
      fromJson: LocationShare.fromJson,
      typeTag: 'LocationShare',
    );
    service = LocationSharingService(shares: shares);
  });

  tearDown(() async {
    await notifStream.close();
  });

  test(
    'startSharingWith creates an active share owned by self, shared with the recipient',
    () async {
      final point = LocationPoint(latitude: 1, longitude: 2);

      final share = await service.startSharingWith(bob, point: point);

      expect(share.owner, self);
      expect(share.sharedWith, {bob});
      expect(share.obj.status, LocationShareStatus.active);
      expect(share.obj.latestPoint?.latitude, 1);
    },
  );

  test('startSharingWith writes one self key and one recipient key', () async {
    final share = await service.startSharingWith(
      bob,
      point: LocationPoint(latitude: 1, longitude: 2),
    );

    final written = verify(
      () => atClient.put(captureAny(), any()),
    ).captured.cast<AtKey>().map((k) => k.toString()).toList();

    expect(
      written,
      containsAll([
        '${share.id}.$namespace$selfAtSignStr',
        '$bobStr:${share.id}.$namespace$selfAtSignStr',
      ]),
    );
  });

  test(
    'publishCurrentLocation rewrites the latest point on every active owned share',
    () async {
      final created = await service.startSharingWith(
        bob,
        point: LocationPoint(latitude: 1, longitude: 2),
      );
      final selfKey = AtKey.fromString(
        '${created.id}.$namespace$selfAtSignStr',
      );

      // `created`'s self key now "exists" in the fake keystore.
      when(
        () => atClient.getAtKeys(regex: any(named: 'regex')),
      ).thenAnswer((_) async => [selfKey]);
      when(() => atClient.get(any())).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'LocationShare',
          'obj': created.obj.toJson(),
        });
        v.metadata = Metadata()
          ..createdAt = created.createdAt
          ..expiresAt = created.expiresAt;
        return v;
      });

      await service.publishCurrentLocation(
        LocationPoint(latitude: 9, longitude: 9),
      );

      final written = verify(
        () => atClient.put(any(that: isA<AtKey>()), captureAny()),
      ).captured.cast<String>();
      final publishedPoints = written
          .map((json) => jsonDecode(json) as Map<String, dynamic>)
          .map((envelope) => envelope['obj'] as Map<String, dynamic>)
          .map((obj) => obj['latestPoint'] as Map<String, dynamic>);
      expect(publishedPoints, anyElement(containsPair('latitude', 9)));
    },
  );

  test('publishCurrentLocation renews expiresAt instead of keeping the '
      'original one', () async {
    // Started with a short expiry, far short of defaultExpiration, so a
    // renewal is unambiguous: if the fix regressed back to reusing
    // `share.expiresAt`, the written expiresAt would stay close to
    // `created.expiresAt` instead of landing near `now + 1 hour`.
    final created = await service.startSharingWith(
      bob,
      point: LocationPoint(latitude: 1, longitude: 2),
      expiresIn: const Duration(seconds: 1),
    );
    final selfKey = AtKey.fromString('${created.id}.$namespace$selfAtSignStr');

    when(
      () => atClient.getAtKeys(regex: any(named: 'regex')),
    ).thenAnswer((_) async => [selfKey]);
    when(() => atClient.get(any())).thenAnswer((_) async {
      final v = AtValue();
      v.value = jsonEncode({
        'type': 'LocationShare',
        'obj': created.obj.toJson(),
      });
      v.metadata = Metadata()
        ..createdAt = created.createdAt
        ..expiresAt = created.expiresAt;
      return v;
    });

    final beforePublish = DateTime.now().toUtc();
    await service.publishCurrentLocation(
      LocationPoint(latitude: 9, longitude: 9),
    );

    final writtenKeys = verify(
      () => atClient.put(captureAny(), any()),
    ).captured.cast<AtKey>();
    // `lastWhere`, not `firstWhere`: `startSharingWith` already wrote the
    // self key once with the original short expiry, so the first match
    // would be that write rather than the renewal from
    // `publishCurrentLocation`.
    final selfWrite = writtenKeys.lastWhere(
      (k) => k.toString() == selfKey.toString(),
    );

    expect(
      selfWrite.metadata.expiresAt!.isAfter(created.expiresAt),
      isTrue,
      reason: 'renewed expiresAt must move past the original short expiry',
    );
    expect(
      selfWrite.metadata.expiresAt!.isAfter(
        beforePublish.add(const Duration(minutes: 50)),
      ),
      isTrue,
      reason:
          'renewed expiresAt should land near now + defaultExpiration '
          '(1 hour), not near the original expiry',
    );
  });

  test(
    'stopSharingWith deletes a share whose only recipient is removed',
    () async {
      final created = await service.startSharingWith(
        bob,
        point: LocationPoint(latitude: 1, longitude: 2),
      );
      final selfKey = AtKey.fromString(
        '${created.id}.$namespace$selfAtSignStr',
      );
      final recipientKey = AtKey.fromString(
        '$bobStr:${created.id}.$namespace$selfAtSignStr',
      );

      // Partition by regex shape: a direct-item scan uses `[^.]+\.<ns>@`
      // while delete's descendant scan uses `.+\.<id>\.<ns>@`, which this
      // service never creates any of — descendants must stay empty so
      // delete() doesn't think `created` has children to cascade.
      when(() => atClient.getAtKeys(regex: any(named: 'regex'))).thenAnswer((
        invocation,
      ) async {
        final regex = invocation.namedArguments[#regex] as String;
        if (regex.contains(r'.+\.') && !regex.contains(r'[^.]+\.')) {
          return <AtKey>[];
        }
        return [selfKey, recipientKey];
      });
      when(() => atClient.get(selfKey)).thenAnswer((_) async {
        final v = AtValue();
        v.value = jsonEncode({
          'type': 'LocationShare',
          'obj': created.obj.toJson(),
        });
        v.metadata = Metadata()
          ..createdAt = created.createdAt
          ..expiresAt = created.expiresAt;
        return v;
      });

      await service.stopSharingWith(bob);

      final deleted = verify(
        () => atClient.delete(captureAny()),
      ).captured.cast<AtKey>().map((k) => k.toString()).toList();
      expect(deleted, contains(selfKey.toString()));
      expect(deleted, contains(recipientKey.toString()));
    },
  );
}
