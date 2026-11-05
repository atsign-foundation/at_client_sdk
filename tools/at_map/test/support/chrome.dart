import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The Chrome to drive: CHROME_EXECUTABLE, else the usual install paths.
String chromeExecutable() {
  final env = Platform.environment['CHROME_EXECUTABLE'];
  if (env != null && env.isNotEmpty) return env;
  const mac = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  if (File(mac).existsSync()) return mac;
  for (final name in [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser'
  ]) {
    final r = Process.runSync('which', [name]);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  }
  fail('these tests open the page in Chrome; set CHROME_EXECUTABLE');
}

/// Headless Chrome, driven over the DevTools protocol.
class Chrome {
  Chrome._(this._process, this._socket, this._profile) {
    _socket.listen(_onMessage);
  }

  final Process _process;
  final WebSocket _socket;
  final Directory _profile;
  int _id = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  final Map<String, Page> _pages = {};

  /// Starts Chrome with a throwaway profile.
  static Future<Chrome> start() async {
    final profile = await Directory.systemTemp.createTemp('at_map_chrome');
    final process = await Process.start(chromeExecutable(), [
      '--headless=new',
      '--remote-debugging-port=0',
      '--user-data-dir=${profile.path}',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-gpu',
      '--disable-extensions',
      '--disable-background-networking',
      '--disable-component-update',
      '--disable-sync',
      '--use-mock-keychain',
      '--password-store=basic',
      'about:blank',
    ]);
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final port = File(p.join(profile.path, 'DevToolsActivePort'));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!port.existsSync() || port.readAsLinesSync().length < 2) {
      if (DateTime.now().isAfter(deadline)) {
        process.kill();
        fail('Chrome did not open its debugging port');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final lines = port.readAsLinesSync();
    final socket =
        await WebSocket.connect('ws://127.0.0.1:${lines[0]}${lines[1]}');
    return Chrome._(process, socket, profile);
  }

  void _onMessage(dynamic raw) {
    final m = jsonDecode(raw as String) as Map<String, Object?>;
    final id = m['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (m['error'] != null) {
        c?.completeError(StateError('${m['error']}'));
      } else {
        c?.complete((m['result'] as Map<String, Object?>?) ?? const {});
      }
      return;
    }
    final session = m['sessionId'] as String?;
    if (session != null) _pages[session]?._event(m);
  }

  Future<Map<String, Object?>> _send(String method,
      [Map<String, Object?> params = const {}, String? session]) {
    final id = ++_id;
    final c = Completer<Map<String, Object?>>();
    _pending[id] = c;
    _socket.add(jsonEncode({
      'id': id,
      'method': method,
      'params': params,
      if (session != null) 'sessionId': session,
    }));
    return c.future.timeout(const Duration(seconds: 30));
  }

  /// Opens [url] in a new tab once its document has been parsed.
  Future<Page> open(String url) async {
    final t = await _send('Target.createTarget', {'url': 'about:blank'});
    final a = await _send(
        'Target.attachToTarget', {'targetId': t['targetId'], 'flatten': true});
    final session = a['sessionId'] as String;
    final page = Page._(this, session);
    _pages[session] = page;
    await _send('Network.enable', {}, session);
    await _send('Page.enable', {}, session);
    await _send('Runtime.enable', {}, session);
    final loaded = page._next('Page.domContentEventFired');
    await _send('Page.navigate', {'url': url}, session);
    await loaded;
    return page;
  }

  /// Stops Chrome and removes its profile.
  Future<void> close() async {
    await _socket.close();
    _process.kill();
    await _process.exitCode;
    await _profile.delete(recursive: true);
  }
}

/// One tab.
class Page {
  Page._(this._chrome, this._session);

  final Chrome _chrome;
  final String _session;

  /// Every URL the tab requested.
  final List<String> requests = [];

  /// Console errors and uncaught exceptions.
  final List<String> errors = [];

  /// Dialogs that opened, such as an alert.
  final List<String> dialogs = [];

  final Map<String, List<Completer<void>>> _waiting = {};

  Future<void> _next(String method) {
    final c = Completer<void>();
    (_waiting[method] ??= []).add(c);
    return c.future.timeout(const Duration(seconds: 30));
  }

  void _event(Map<String, Object?> m) {
    final method = m['method'] as String;
    final params = (m['params'] as Map<String, Object?>?) ?? const {};
    for (final c in _waiting.remove(method) ?? const <Completer<void>>[]) {
      c.complete();
    }
    switch (method) {
      case 'Network.requestWillBeSent':
        requests.add(((params['request'] as Map)['url']) as String);
      case 'Runtime.exceptionThrown':
        errors.add(jsonEncode(params['exceptionDetails']));
      case 'Runtime.consoleAPICalled':
        if (params['type'] == 'error') errors.add(jsonEncode(params['args']));
      case 'Page.javascriptDialogOpening':
        dialogs.add('${params['message']}');
        _chrome._send(
            'Page.handleJavaScriptDialog', {'accept': true}, _session);
    }
  }

  /// The value of [expression], awaited when it is a promise.
  Future<Object?> eval(String expression) async {
    final r = await _chrome._send(
        'Runtime.evaluate',
        {
          'expression': expression,
          'returnByValue': true,
          'awaitPromise': true,
        },
        _session);
    if (r['exceptionDetails'] != null) {
      throw StateError('page threw: ${jsonEncode(r['exceptionDetails'])}');
    }
    return (r['result'] as Map<String, Object?>)['value'];
  }

  /// Waits until [condition] is true in the page.
  Future<void> waitFor(String condition,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final deadline = DateTime.now().add(timeout);
    while (await eval('Boolean($condition)') != true) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $condition; page errors: $errors');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Selects [step] the way a reader does, by its box, and waits for the
  /// panel.
  Future<void> select(String flow, String step) async {
    await eval('document.querySelector(\'g.step[data-step="$step"]\')'
        '.dispatchEvent(new MouseEvent("click", {bubbles: true}))');
    await waitFor('document.body.getAttribute("data-ready") === "$flow.$step"');
  }
}
