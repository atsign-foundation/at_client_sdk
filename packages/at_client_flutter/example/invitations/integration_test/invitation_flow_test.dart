import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:invitations/incoming.dart';
import 'package:invitations/issuer.dart' show issuerUrl;
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

  setUpAll(() async {
    Session.keyfileDirectory = Directory.systemTemp
        .createTempSync('invitations_keys')
        .path;
    await Incoming.instance.start();
  });

  testWidgets('an invitation is created, accepted, confirmed and read', (
    tester,
  ) async {
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
    await waitFor(
      tester,
      find.text('Encrypted: you can read it once Alice confirms you'),
    );
    await signOut(tester);

    // Alice's app, while it is open, confirms Bob and says so.
    await tapText(tester, 'Sign in as $alice');
    await waitFor(
      tester,
      find.text('Bob Brown accepted'),
      timeout: const Duration(seconds: 90),
    );
    expect(
      find.textContaining('sent them the key to the private content'),
      findsOneWidget,
    );
    await tapText(tester, 'OK');
    await waitFor(tester, find.text('accepted by $bob (Bob Brown)'));
    await tapText(tester, 'Contacts');
    await waitFor(tester, find.text(bob));
    final bobsContact = find.ancestor(
      of: find.text(bob),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: bobsContact, matching: find.text('Bob Brown')),
      findsOneWidget,
      reason: 'the contact takes the name the invitee gave',
    );
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
    await signOut(tester);
  });

  testWidgets('the accept screen switches atSign and back, and signing out '
      'needs no atServer', (tester) async {
    await tester.pumpWidget(const InvitationsApp());

    // Alice invites Dan, and Carol has an atSign on this device too.
    await tapText(tester, 'Get a new atSign');
    final alice = await appBarAtSign(tester);
    await tapText(tester, 'Invite');
    await enter(tester, 'Who are you inviting?', 'Dan');
    await enter(tester, 'Your name, as they will see it', 'Alice');
    await tapText(tester, 'Create invitation');
    final link = await copyable(tester, 'The link');
    final code = await copyable(tester, 'The code');
    await tester.pageBack();
    await signOut(tester);
    await tapText(tester, 'Get a new atSign');
    final carol = await appBarAtSign(tester);
    await signOut(tester);

    // Dan opens the invitation, switches to Carol and back, and accepts.
    await tapText(tester, 'Paste an invitation');
    await tester.enterText(
      find.widgetWithText(TextField, 'The invitation link you were sent'),
      link,
    );
    await tapText(tester, 'Open');
    await waitFor(tester, find.textContaining('$alice invited you'));
    await tapText(tester, 'Get a new atSign');
    final dan = await appBarAtSign(tester);
    await waitFor(tester, find.text('Alice ($alice) invited you'));
    await acceptAs(tester, carol);
    await expectAcceptingAs(tester, carol);
    await acceptAs(tester, dan);
    await expectAcceptingAs(tester, dan);

    // A switch that fails leaves Dan signed in, and the field saying so.
    var offline = false;
    addTearDown(() async {
      if (offline) await setEeOnline(true);
    });
    await setEeOnline(false);
    offline = true;
    await acceptAs(tester, carol);
    await waitFor(
      tester,
      find.textContaining('Could not switch to $carol'),
      timeout: const Duration(seconds: 120),
    );
    await expectAcceptingAs(tester, dan);
    await setEeOnline(true);
    offline = false;

    await enter(tester, 'The code Alice sent you', code);
    await tapText(tester, 'Accept');
    await waitFor(tester, find.textContaining('Invitations — $dan'));

    // Dan signs out while the atServer cannot be reached, and signs in
    // again once it can.
    await setEeOnline(false);
    offline = true;
    await signOut(tester, timeout: const Duration(seconds: 90));
    await setEeOnline(true);
    offline = false;
    await tapText(tester, 'Sign in as $dan');
    await waitFor(
      tester,
      find.textContaining('Invitations — $dan'),
      timeout: const Duration(seconds: 120),
    );
    await signOut(tester);
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
  final onScreen = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .nonNulls
      .join(' | ');
  throw TestFailure(
    'Timed out after $timeout waiting for $finder. On screen: $onScreen',
  );
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

/// Signs out from the home screen, once the button can take the tap: after
/// a page closes, it is found while the page's exit transition still covers
/// it.
Future<void> signOut(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final button = find.byTooltip('Sign out').hitTestable();
  await waitFor(tester, button);
  await tester.tap(button);
  await waitFor(tester, find.text('Get a new atSign'), timeout: timeout);
}

/// Chooses [atSign] under "Accept as".
Future<void> acceptAs(WidgetTester tester, String atSign) async {
  final field = find.byType(DropdownButton<String>);
  await waitFor(tester, field);
  await tester.tap(field);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text(atSign).last);
  await tester.pump(const Duration(milliseconds: 500));
}

/// Waits until "Accept as" can be changed again and shows [atSign], and
/// checks that the session holds that atSign too.
Future<void> expectAcceptingAs(WidgetTester tester, String atSign) async {
  await waitFor(
    tester,
    find.byWidgetPredicate(
      (w) =>
          w is DropdownButton<String> &&
          w.value == atSign &&
          w.onChanged != null,
    ),
    timeout: const Duration(seconds: 120),
  );
  expect(
    Session.instance.invitations?.me.toString(),
    atSign,
    reason: 'the field shows the atSign the invitation will be accepted as',
  );
}

/// Disconnects the Ephemeral Environment from its network, or reconnects
/// it, through the issuer `ee/up.sh` started.
Future<void> setEeOnline(bool online) async {
  final response = await http.post(
    Uri.parse('$issuerUrl/ee/${online ? 'online' : 'offline'}'),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'The issuer could not change the network: ${response.body}',
    );
  }
}
