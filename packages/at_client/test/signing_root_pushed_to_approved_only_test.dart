import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show AtClientSecretSharing;
import 'package:at_commons/at_builders.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'test_utils/mocks.dart';
import 'test_utils/remote_backed_client.dart';

/// Which enrollments a freshly minted signing root's private is pushed to.
///
/// Catalogue: docs/projects/pq/acceptance.md UC-A3.7
void main() {
  const atSign = '@alice';
  const full = {'*': 'rw', '__manage': 'rw'};
  const notApproved = ['pending', 'denied', 'revoked', 'expired'];

  setUpAll(() {
    registerFallbackValue(FakeUpdateVerbBuilder());
    registerFallbackValue(FakeAtKey());
  });

  group(
      'UC-A3.7 · Given a fully privileged enrollment that mints the root, and '
      'fully privileged enrollments that are approved, pending, denied, '
      'revoked and expired, each listed with a verified key package', () {
    late Map<String, String> remoteData;

    setUp(() => remoteData = {});

    /// A client of the atSign over [remoteData].
    AtClient member(String enrollmentId) => buildRemoteBackedMockClient(
        atSign: atSign, enrollmentId: enrollmentId, remoteData: remoteData);

    Enrollment fullyPrivileged(String id, String status) => Enrollment()
      ..enrollmentId = id
      ..status = status
      ..namespace = full;

    Future<Map<String, dynamic>> listed(String id, {AtClient? holder}) async =>
        {
          'enrollmentId': id,
          'access': 'rw',
          'metadata': {
            if (holder != null)
              'keyPackage': (await AtClientSecretSharing.forClient(holder)
                      .signedKeyPackagePayload())
                  .toJson(),
          },
        };

    /// The minting client: its atServer writes land in [remoteData], its
    /// enrollment list is [enrollments], and `__manage` lists [roster].
    Future<AtClient> minter(
        {required List<Enrollment> enrollments,
        required List<Map<String, dynamic>> roster}) async {
      final atClient = member('minter');
      final secondary = atClient.getRemoteSecondary()!;
      when(() => secondary.executeVerb(any(that: isA<UpdateVerbBuilder>())))
          .thenAnswer((inv) async {
        final builder = inv.positionalArguments[0] as UpdateVerbBuilder;
        remoteData['${builder.atKey}'] = '${builder.value}';
        return 'data:1';
      });
      when(() => secondary.executeCommand(
              any(that: startsWith('enroll:listns:__manage')),
              auth: any(named: 'auth')))
          .thenAnswer((_) async => 'data:${jsonEncode(roster)}');
      final service = MockEnrollmentService();
      when(() => service.fetchEnrollmentRequests(
              enrollmentListParams: any(named: 'enrollmentListParams')))
          .thenAnswer((_) async => enrollments);
      when(() => atClient.enrollmentService).thenReturn(service);
      await AtClientSecretSharing.forClient(atClient).register();
      return atClient;
    }

    test(
        'when it publishes, then only the approved enrollment receives its '
        'private', () async {
      final approved = member('approved-1');
      final approvedSharing = AtClientSecretSharing.forClient(approved);
      await approvedSharing.register();
      final others = <String, AtClientSecretSharing>{};
      final roster = [
        await listed('minter'),
        await listed('approved-1', holder: approved),
      ];
      for (final status in notApproved) {
        final client = member('$status-1');
        others[status] = AtClientSecretSharing.forClient(client);
        await others[status]!.register();
        roster.add(await listed('$status-1', holder: client));
      }
      final minting = await minter(enrollments: [
        fullyPrivileged('minter', 'approved'),
        fullyPrivileged('approved-1', 'approved'),
        for (final status in notApproved) fullyPrivileged('$status-1', status),
      ], roster: roster);
      final root = PqSigningRoot(minting, keysIo: minting.atKeysIo);

      expect(await root.mintIfAbsent(isFullyPrivileged: true), isNotNull);

      expect(await approvedSharing.sweepOnce(), greaterThan(0),
          reason: 'the control: an approved, fully privileged enrollment '
              'listed beside the others is pushed the private, so a sweep '
              'that finds nothing below is about the status');
      final received = approvedSharing.secretStore
          .getSecret('wavi', PqSigningRoot.secretName);
      expect(received, isNotNull);
      expect(base64Decode(received!.value),
          (await root.signingKey(atSign))!.private);

      final sweptBy = {
        for (final MapEntry(key: status, value: sharing) in others.entries)
          status: await sharing.sweepOnce()
      };
      expect(sweptBy, {for (final status in notApproved) status: 0},
          reason: 'only an approved enrollment is pushed the signing root '
              'private; one that is fully privileged and listed with a '
              'verified key package but not approved is pushed nothing');
      for (final MapEntry(key: status, value: sharing) in others.entries) {
        expect(sharing.secretStore.getSecret('wavi', PqSigningRoot.secretName),
            isNull,
            reason: 'a $status enrollment holds no signing root private');
      }
    });
  });
}
