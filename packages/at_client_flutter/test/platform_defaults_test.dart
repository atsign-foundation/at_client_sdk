import 'dart:io';

import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_path_provider.dart';

class _AppFlows extends Mock implements AtsignFlows {}

class _FakePreference extends Fake implements AtClientPreference {}

/// The platform defaults as an app reaches them, through this package's one
/// import and nothing under `src/`.
///
/// Catalogue: features/at_client_flutter/platform_defaults.feature
void main() {
  late Directory support;

  setUpAll(() {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(_FakePreference());
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('app_support_');
    PathProviderPlatform.instance = FakePathProvider(support.path);
  });

  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('A widget test stands in for the verbs a dialog runs', (
    tester,
  ) async {
    final flows = _AppFlows();
    when(
      () => flows.open(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) => Future.error(Exception('refused')));

    Object? result = 'unset';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => result = await showDialog<Object?>(
                context: context,
                builder: (_) => PkamDialog(
                  atSign: '@alice',
                  keys: InMemoryAtKeysIo(),
                  preference: AtClientPreference(),
                  flows: flows,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    verify(
      () => flows.open(
        '@alice',
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
      ),
    ).called(1);
    await tester.pumpAndSettle();
    expect(result, isNull, reason: 'the dialog popped with no client');
  });

  test(
    'With no store named, the default is Hive in the app\'s support directory',
    () async {
      final storage = await storageOrDefault('@alice', AtClientPreference());
      expect(
        storage,
        isA<HiveAtClientStorage>()
            .having((s) => s.storagePath, 'storagePath', support.path)
            .having((s) => s.atSign, 'atSign', '@alice')
            .having((s) => s.closedByClient, 'closedByClient', isTrue),
      );
    },
  );
}
