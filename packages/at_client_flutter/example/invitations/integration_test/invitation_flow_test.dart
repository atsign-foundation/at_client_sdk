import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:invitations/incoming.dart';
import 'package:invitations/main.dart';
import 'package:invitations/session.dart';

/// Drives the whole flow through the app's screens against the Ephemeral
/// Environment `ee/up.sh` starts, playing both people in turn on one device:
/// Alice invites, Bob accepts, Alice's app confirms him, and Bob reads the
/// content.
///
/// Run with `ee/up.sh` first, then
/// `flutter test integration_test -d macos`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an invitation is created, accepted, confirmed and read', (
    tester,
  ) async {
    Session.keyfileDirectory = Directory.systemTemp
        .createTempSync('invitations_keys')
        .path;
    await Incoming.instance.start();
    await tester.pumpWidget(const InvitationsApp());

    // Alice gets an atSign and invites Bob.
    await tapText(tester, 'Get a new atSign');
    final alice = await appBarAtSign(tester);
    await tapText(tester, 'Invite');
    await enter(tester, 'Who are you inviting?', 'Bob');
    await enter(tester, 'Your name, as they will see it', 'Alice');
    await enter(tester, 'A message (optional)', 'Join me');
    await enter(tester, 'Something private for them (optional)', 'the recipe');
    await tapText(tester, 'Create invitation');
    final link = await copyable(tester, 'The link');
    final code = await copyable(tester, 'The code');
    expect(link, contains('#$alice/'));
    expect(code, matches(RegExp(r'^\d{6}$')));
    debugPrint('alice=$alice link=$link code=$code');
    await tester.pageBack();
    await signOut(tester);

    // Bob pastes the link, gets an atSign, and accepts.
    await tapText(tester, 'Paste an invitation');
    await tester.enterText(
      find.widgetWithText(TextField, 'The invitation link you were sent'),
      link,
    );
    await tapText(tester, 'Open');
    await waitFor(tester, find.textContaining('$alice invited you'));
    await tapText(tester, 'Get a new atSign');
    final bob = await appBarAtSign(tester);
    debugPrint('bob=$bob');
    await waitFor(tester, find.text('Alice ($alice) invited you'));
    expect(find.textContaining('Private content came with it'), findsOneWidget);
    await enter(tester, 'The code Alice sent you', code);
    await enter(tester, 'Your name, as Alice will see it', 'Bob Brown');
    await tapText(tester, 'Accept');
    await waitFor(tester, find.textContaining('Invitations — $bob'));
    await signOut(tester);

    // Alice's app, while it is open, confirms Bob.
    await tapText(tester, 'Sign in as $alice');
    await tapText(tester, 'Sent', timeout: const Duration(seconds: 60));
    await waitFor(
      tester,
      find.text('accepted by $bob (Bob Brown)'),
      timeout: const Duration(seconds: 90),
    );
    await tapText(tester, 'Contacts');
    await waitFor(tester, find.text(bob));
    await signOut(tester);

    // Bob is connected, and reads the content.
    await tapText(tester, 'Sign in as $bob');
    await waitFor(
      tester,
      find.text('the recipe'),
      timeout: const Duration(seconds: 90),
    );
    await tapText(tester, 'Contacts');
    await waitFor(tester, find.text(alice));
  });
}

/// Pumps until [finder] finds something, failing after [timeout].
///
/// Real network I/O happens between pumps; pumpAndSettle would never return,
/// because the home screen's processing timer keeps scheduling frames.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out after $timeout waiting for $finder');
}

Future<void> tapText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final finder = find.text(text).last;
  await waitFor(tester, find.text(text), timeout: timeout);
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextField, label);
  await waitFor(tester, field);
  await tester.enterText(field, text);
}

/// The atSign the home screen's title names, once it shows.
Future<String> appBarAtSign(WidgetTester tester) async {
  final title = find.textContaining('Invitations — @');
  await waitFor(tester, title, timeout: const Duration(seconds: 120));
  return tester.widget<Text>(title).data!.split('— ').last;
}

/// The value shown under [label] on the invitation-created screen.
Future<String> copyable(WidgetTester tester, String label) async {
  final tile = find.widgetWithText(ListTile, label);
  await waitFor(tester, tile);
  final text = find.descendant(of: tile, matching: find.byType(SelectableText));
  return tester.widget<SelectableText>(text).data!;
}

Future<void> signOut(WidgetTester tester) async {
  await waitFor(tester, find.byTooltip('Sign out'));
  await tester.tap(find.byTooltip('Sign out'));
  await waitFor(tester, find.text('Get a new atSign'));
}
