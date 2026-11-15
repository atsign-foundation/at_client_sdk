@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/src/static_server.dart';

void main() {
  late Directory root;
  late StaticServer server;
  final client = HttpClient();

  setUp(() async {
    final tmp = Directory.systemTemp.createTempSync('static_server_test');
    root = Directory('${tmp.path}/build')..createSync();
    File('${tmp.path}/secret.txt').writeAsStringSync('outside the root');
    File('${root.path}/index.html').writeAsStringSync('<h1>index</h1>');
    File('${root.path}/at_client.wasm').writeAsBytesSync([0, 0x61, 0x73, 0x6d]);
    File('${root.path}/at_client.mjs').writeAsStringSync('export {};');
    File('${root.path}/at_client.js').writeAsStringSync('//js');
    server = await serveStatic(root, port: 0);
  });

  tearDown(() async {
    await server.close();
    root.parent.deleteSync(recursive: true);
  });

  tearDownAll(() => client.close(force: true));

  Future<HttpClientResponse> get(String path) async {
    final request = await client.get('localhost', server.port, path);
    return request.close();
  }

  test('serves a file with its content type', () async {
    final cases = {
      '/index.html': 'text/html; charset=utf-8',
      '/at_client.js': 'text/javascript; charset=utf-8',
      '/at_client.mjs': 'text/javascript; charset=utf-8',
      '/at_client.wasm': 'application/wasm',
    };
    for (final MapEntry(key: path, value: type) in cases.entries) {
      final response = await get(path);
      expect(response.statusCode, 200, reason: path);
      expect(response.headers.value('content-type'), type, reason: path);
      await response.drain<void>();
    }
  });

  test('serves the bytes of the file', () async {
    final response = await get('/index.html');
    expect(await utf8.decodeStream(response), '<h1>index</h1>');
  });

  test('sends Cache-Control: no-store on every response', () async {
    for (final path in ['/index.html', '/missing.js', '/%2e%2e/secret.txt']) {
      final response = await get(path);
      expect(response.headers.value('cache-control'), 'no-store', reason: path);
      await response.drain<void>();
    }
  });

  test('serves index.html at the root', () async {
    final response = await get('/');
    expect(response.statusCode, 200);
    expect(await utf8.decodeStream(response), '<h1>index</h1>');
  });

  test('404s a missing file and a directory', () async {
    for (final path in ['/missing.js', '/sub/']) {
      final response = await get(path);
      expect(response.statusCode, 404, reason: path);
      await response.drain<void>();
    }
  });

  test('refuses a path that climbs out of the root', () async {
    for (final path in [
      '/%2e%2e/secret.txt',
      '/..%2fsecret.txt',
      '/a/%2e%2e/%2e%2e/secret.txt',
    ]) {
      final response = await get(path);
      expect(response.statusCode, isIn([403, 404]), reason: path);
      expect(await utf8.decodeStream(response), isNot(contains('outside')),
          reason: path);
    }
  });

  test('listens on IPv4 and IPv6 loopback so localhost resolves either way',
      () async {
    for (final host in [
      InternetAddress.loopbackIPv4,
      InternetAddress.loopbackIPv6
    ]) {
      final request =
          await client.get(host.address, server.port, '/index.html');
      final response = await request.close();
      expect(response.statusCode, 200, reason: host.address);
      await response.drain<void>();
    }
  });
}
