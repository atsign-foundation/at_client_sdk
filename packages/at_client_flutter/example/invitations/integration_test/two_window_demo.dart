import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invitations/incoming.dart';
import 'package:invitations/main.dart';
import 'package:invitations/session.dart';

/// Plays the invitation flow at a pace a viewer can follow, as one of two
/// instances side by side: Alice or Bob, as `DEMO_ROLE` says.
///
/// `demo/demo.sh` builds the app with this as its entry point and runs both.
/// They hand the link and code over through the app's temporary directory,
/// which the two instances share, standing in for sending them out of band.
/// It is not a test: `flutter test integration_test` runs only `*_test.dart`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final role = Platform.environment['DEMO_ROLE'] ?? 'alice';
  final handoff = _Handoff(Directory.systemTemp.path);

  testWidgets('demo as $role', (tester) async {
    Session.keyfileDirectory = Directory.systemTemp
        .createTempSync('demo_keys_$role')
        .path;
    await Incoming.instance.start();
    await tester.pumpWidget(const InvitationsApp());
    await _pause(tester, 2);
    if (role == 'alice') {
      await _alice(tester, handoff);
    } else {
      await _bob(tester, handoff);
    }
    await _pause(tester, 2);
    debugPrint('DEMO $role finished');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// The files the two instances signal each other with. `demo.sh` writes
/// [go] once recording has started, and puts the link on the clipboard.
class _Handoff {
  final File invitation;

  _Handoff(String dir)
    : invitation = File('$dir/invitations_demo_handoff.json');

  File get go => File('${invitation.path}.go');
  File get bobAccepted => File('${invitation.path}.accepted');
  File get aliceShown => File('${invitation.path}.alice');
  File get bobDone => File('${invitation.path}.done');
}

/// Invites Bob, then goes offline so that nothing of Alice's can confirm
/// him, and comes back once he has accepted: her app confirms him then.
Future<void> _alice(WidgetTester tester, _Handoff handoff) async {
  for (final f in [
    handoff.invitation,
    handoff.bobAccepted,
    handoff.aliceShown,
    handoff.bobDone,
  ]) {
    if (f.existsSync()) f.deleteSync();
  }
  await _waitForFile(tester, handoff.go);
  await _tapText(tester, 'Get a new atSign');
  final title = find.textContaining('Invitations — @');
  await _waitFor(tester, title, minutes: 2);
  final me = tester.widget<Text>(title).data!.split('— ').last;
  await _pause(tester, 2);
  await _tapText(tester, 'Invite');
  await _pause(tester, 1);
  await _type(tester, 'Who are you inviting?', 'Bob');
  await _type(tester, 'Your name, as they will see it', 'Alice');
  await _type(tester, 'A message (optional)', 'Join my book club!');
  await _type(
    tester,
    'Something private for them (optional)',
    'Chapter one is on me: Thursday at 7.',
  );
  await _pause(tester, 1);
  await _tapText(tester, 'Create invitation');
  final link = await _copyable(tester, 'The link');
  final code = await _copyable(tester, 'The code');
  await _pause(tester, 4);
  handoff.invitation.writeAsStringSync(
    jsonEncode({'link': link, 'code': code}),
  );
  await tester.pageBack();
  await _pause(tester, 1);
  await _tapText(tester, 'Sent');
  await _pause(tester, 3);
  final signOut = find.byTooltip('Sign out').hitTestable();
  await _waitFor(tester, signOut);
  await tester.tap(signOut);
  await _waitFor(tester, find.text('Get a new atSign'));
  await _waitForFile(tester, handoff.bobAccepted);
  await _pause(tester, 8);
  await _tapText(tester, 'Sign in as $me');
  await _waitFor(tester, find.text('Bob Brown accepted'), minutes: 3);
  await _pause(tester, 7);
  await _tapText(tester, 'OK');
  await _waitFor(tester, find.textContaining('accepted by'));
  handoff.aliceShown.writeAsStringSync('shown');
  await _waitForFile(tester, handoff.bobDone);
}

/// Opens Alice's invitation, gets an atSign and accepts, then waits with the
/// content sealed until Alice's app confirms him and the key arrives.
Future<void> _bob(WidgetTester tester, _Handoff handoff) async {
  await _waitForFile(tester, handoff.invitation, minutes: 5);
  final invitation = jsonDecode(handoff.invitation.readAsStringSync());
  await _pause(tester, 1);
  await _tapText(tester, 'Paste an invitation');
  final linkField = find.widgetWithText(
    TextField,
    'The invitation link you were sent',
  );
  await _waitFor(tester, linkField);
  await tester.enterText(linkField, invitation['link']);
  await _pause(tester, 2);
  await _tapText(tester, 'Open');
  await _pause(tester, 3);
  await _tapText(tester, 'Get a new atSign');
  await _waitFor(tester, find.textContaining(') invited you'), minutes: 2);
  await _pause(tester, 4);
  await _type(tester, 'The code Alice sent you', invitation['code']);
  await _type(tester, 'Your name, as Alice will see it', 'Bob Brown');
  await _pause(tester, 1);
  await _tapText(tester, 'Accept');
  await _waitFor(tester, find.textContaining('Encrypted: you can read it'));
  await _pause(tester, 1);
  handoff.bobAccepted.writeAsStringSync('accepted');
  await _waitFor(
    tester,
    find.text('Chapter one is on me: Thursday at 7.'),
    minutes: 3,
  );
  await _waitForFile(tester, handoff.aliceShown);
  await _pause(tester, 6);
  handoff.bobDone.writeAsStringSync('done');
}

/// Keeps the app running and rendering for [seconds].
Future<void> _pause(WidgetTester tester, num seconds) async {
  final end = DateTime.now().add(
    Duration(milliseconds: (seconds * 1000).round()),
  );
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForFile(
  WidgetTester tester,
  File file, {
  int minutes = 3,
}) async {
  final end = DateTime.now().add(Duration(minutes: minutes));
  while (!file.existsSync()) {
    if (DateTime.now().isAfter(end)) throw TestFailure('no ${file.path}');
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int minutes = 1,
}) async {
  final end = DateTime.now().add(Duration(minutes: minutes));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  final onScreen = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .nonNulls
      .join(' | ');
  throw TestFailure('Timed out waiting for $finder. On screen: $onScreen');
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final target = find.text(text).hitTestable();
  await _waitFor(tester, target);
  await tester.tap(target.last);
  await tester.pump(const Duration(milliseconds: 250));
}

/// Types [text] into the field labelled [label] a character at a time, then
/// sets it whole, since a keystroke can be lost between frames.
Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await _waitFor(tester, field);
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(field, text.substring(0, i));
    await tester.pump(const Duration(milliseconds: 45));
  }
  await tester.enterText(field, text);
  await _pause(tester, 0.4);
}

Future<String> _copyable(WidgetTester tester, String label) async {
  final tile = find.widgetWithText(ListTile, label);
  await _waitFor(tester, tile);
  final text = find.descendant(of: tile, matching: find.byType(SelectableText));
  return tester.widget<SelectableText>(text).data!;
}
