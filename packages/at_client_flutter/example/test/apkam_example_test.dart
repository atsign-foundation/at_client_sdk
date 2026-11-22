import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:example/apkam_example.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The APKAM example page gets a passcode for another device and files no
/// enrollment request of its own.
///
/// The client the page reads is a fake whose atDirectory is a loopback port
/// that counts each connection made to it, so a page that filed a request
/// through that client's preferences would raise the count.
void main() {
  const atSign = '@alice';
  late ServerSocket atDirectory;
  var connections = 0;

  setUpAll(() async {
    atDirectory = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    atDirectory.listen((socket) {
      connections++;
      socket.destroy();
    });
  });

  tearDownAll(() => atDirectory.close());

  setUp(() {
    connections = 0;
    AtClientManager.getInstance().use(_FakeAtClient(atDirectory.port));
  });

  tearDown(() => AtClientManager.getInstance().reset());

  testWidgets(
    'Given the APKAM example page on an enrolled client, when the user gets '
    'a passcode, then the page shows it with where another device uses it, '
    'and files no enrollment request',
    (tester) async {
      var passcodesGot = 0;
      await tester.runAsync(() async {
        await (await Socket.connect(
          InternetAddress.loopbackIPv4,
          atDirectory.port,
        )).close();
        for (var i = 0; i < 50 && connections == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(
        connections,
        1,
        reason:
            'the control for "files no request": a connection to the '
            "client's atDirectory is counted",
      );
      connections = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ApkamExamplePage(
            getPasscode: () async {
              passcodesGot++;
              return Passcode('ABC123', null);
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Get Passcode'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();

      expect(
        connections,
        0,
        reason: "it files no request: nothing reaches the client's atDirectory",
      );
      expect(passcodesGot, 1, reason: 'it gets one passcode');
      expect(
        find.text('Passcode: ABC123'),
        findsOneWidget,
        reason: 'it shows the passcode',
      );
      expect(
        find.textContaining('"Register an atSign with APKAM"'),
        findsOneWidget,
        reason: "it says to enter it in this example's APKAM registration",
      );
      expect(
        find.text(
          'at_activate enroll -a $atSign -r 127.0.0.1:${atDirectory.port} '
          '--app <app> --device <device> --namespaces <ns:rw> '
          '--passcode ABC123 -k <keyfile>',
        ),
        findsOneWidget,
        reason:
            'it gives the at_activate enroll command that quotes it, at the '
            "client's own root",
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// An enrolled client of @alice whose atDirectory is the loopback port
/// [rootPort], with no pending enrollments and no notifications.
class _FakeAtClient extends Fake implements AtClient {
  _FakeAtClient(this.rootPort);

  final int rootPort;

  @override
  String? getCurrentAtSign() => '@alice';

  @override
  AtClientPreference? getPreferences() => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = rootPort;

  @override
  EnrollmentService? get enrollmentService => _FakeEnrollmentService();

  @override
  NotificationService get notificationService => _FakeNotificationService();
}

/// An enrollment roster with nothing in it.
class _FakeEnrollmentService extends Fake implements EnrollmentService {
  @override
  Future<List<Enrollment>> fetchEnrollmentRequests({
    EnrollmentListRequestParam? enrollmentListParams,
  }) async => [];
}

/// Notifications that never arrive.
class _FakeNotificationService extends Fake implements NotificationService {
  @override
  Stream<AtNotification> subscribe({
    String? regex,
    bool shouldDecrypt = false,
  }) => const Stream.empty();
}
