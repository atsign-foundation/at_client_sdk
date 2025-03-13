import 'dart:io';

import 'package:at_server_status/at_server_status.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('Known @sign tests', () {
    late AtStatus atStatus;
    AtStatusImpl atStatusImpl;
    var atSign = '@13majorfishtaco';
    setUp(() async {
      atStatusImpl = AtStatusImpl();
      atStatus = await atStatusImpl.get(atSign);
    });

    test('rootStatus', () async {
      expect(atStatus.rootStatus, equals(RootStatus.found));
    });

    test('serverStatus', () async {
      expect(atStatus.serverStatus, equals(ServerStatus.activated));
    });

    test('status()', () {
      expect(atStatus.status(), equals(AtSignStatus.activated));
    });

    test('httpStatus()', () {
      expect(atStatus.httpStatus(), equals(HttpStatus.ok));
    });
  });

  group('@sign activation not started tests', () {
    late AtStatus atStatus;
    AtStatusImpl atStatusImpl;
    var atSign = '@small73sepia';
    setUp(() async {
      atStatusImpl = AtStatusImpl();
      atStatus = await atStatusImpl.get(atSign);
    });

    test('rootStatus', () async {
      expect(atStatus.rootStatus, equals(RootStatus.notFound));
    });

    test('serverStatus', () async {
      expect(atStatus.serverStatus, equals(ServerStatus.unavailable));
    });

    test('status()', () {
      expect(atStatus.status(), equals(AtSignStatus.notFound));
    });

    test('httpStatus()', () {
      expect(atStatus.httpStatus(), equals(HttpStatus.notFound));
    });
  });

  group('@sign ready for activation but not activated tests', () {
    late AtStatus atStatus;
    AtStatusImpl atStatusImpl;
    var atSign = '@bullridingcapable';
    setUp(() async {
      atStatusImpl = AtStatusImpl();
      atStatus = await atStatusImpl.get(atSign);
    });

    test('rootStatus', () async {
      expect(atStatus.rootStatus, equals(RootStatus.found));
    });

    test('serverStatus', () async {
      expect(atStatus.serverStatus, equals(ServerStatus.teapot));
    });

    test('status()', () {
      expect(atStatus.status(), equals(AtSignStatus.teapot));
    });

    test('httpStatus', () {
      expect(atStatus.httpStatus(), equals(418));
    });
  });

  group('@sign does not exist tests', () {
    var uuid = Uuid();
    late AtStatus atStatus;
    AtStatusImpl atStatusImpl;
    var atSign = uuid.v4();
    print(atSign);
    setUp(() async {
      atStatusImpl = AtStatusImpl();
      atStatus = await atStatusImpl.get(atSign);
    });

    test('rootStatus', () async {
      expect(atStatus.rootStatus, equals(RootStatus.notFound));
    });

    test('serverStatus', () async {
      expect(atStatus.serverStatus, equals(ServerStatus.unavailable));
    });

    test('status()', () {
      expect(atStatus.status(), equals(AtSignStatus.notFound));
    });

    test('httpStatus', () {
      expect(atStatus.httpStatus(), equals(HttpStatus.notFound));
    });
  });
}
