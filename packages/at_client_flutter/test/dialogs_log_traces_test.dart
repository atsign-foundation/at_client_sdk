import 'package:at_client_flutter/at_client_flutter.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger, LoggingHandler;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAtsignFlows extends Mock implements AtsignFlows {}

class _FakeAtClientPreference extends Fake implements AtClientPreference {}

class _FakeAtClientStorage extends Fake implements AtClientStorage {}

/// Every record logged, kept whole.
class _KeptLogs implements LoggingHandler {
  final List<dynamic> records = [];

  @override
  void call(dynamic record) => records.add(record);
}

/// A dialog whose operation fails keeps the stack trace out of what it shows
/// and logs it at fine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final logs = _KeptLogs();
  late _MockAtsignFlows flows;

  setUpAll(() {
    registerFallbackValue(InMemoryAtKeysIo());
    registerFallbackValue(_FakeAtClientPreference());
    registerFallbackValue(_FakeAtClientStorage());
    // NOTE: before any dialog builds its logger, which binds the handler and
    // the level it finds.
    AtSignLogger.defaultLoggingHandler = logs;
    AtSignLogger.root_level = 'finest';
  });

  setUp(() {
    flows = _MockAtsignFlows();
    logs.records.clear();
  });

  Future<void> runDialog(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showDialog<Object?>(context: context, builder: (_) => dialog),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The fine records whose message starts with [message].
  Iterable<dynamic> fineRecords(String message) => logs.records.where(
    (r) => '${r.level.name}' == 'FINE' && '${r.message}'.startsWith(message),
  );

  testWidgets('PkamDialog logs the stack trace of its failure at fine', (
    tester,
  ) async {
    when(
      () => flows.open(
        any(),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
      ),
    ).thenAnswer((_) => Future.error(Exception('boom')));

    await runDialog(
      tester,
      PkamDialog(
        atSign: '@alice',
        keys: InMemoryAtKeysIo(),
        preference: AtClientPreference(),
        flows: flows,
      ),
    );

    final records = fineRecords('Authentication via PKAM failed');
    expect(records, isNotEmpty, reason: 'the failure is logged at fine');
    expect(records.first.stackTrace, isNotNull, reason: 'with its trace');
  });

  testWidgets('CramDialog logs the stack trace of its failure at fine', (
    tester,
  ) async {
    when(
      () => flows.activate(
        any(),
        cramSecret: any(named: 'cramSecret'),
        keys: any(named: 'keys'),
        preference: any(named: 'preference'),
        storage: any(named: 'storage'),
        lookUps: any(named: 'lookUps'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) => Future.error(Exception('boom')));

    await runDialog(
      tester,
      CramDialog(
        atSign: '@alice',
        cramKey: 'cram-secret-6d1f0b',
        preference: AtClientPreference(),
        keys: InMemoryAtKeysIo(),
        flows: flows,
      ),
    );

    final records = fineRecords('Onboarding via CRAM failed');
    expect(records, isNotEmpty, reason: 'the failure is logged at fine');
    expect(records.first.stackTrace, isNotNull, reason: 'with its trace');
  });
}
