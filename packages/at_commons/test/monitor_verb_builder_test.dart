import 'package:at_commons/at_builders.dart';
import 'package:test/test.dart';

void main() {
  int nowEpochMillis = DateTime.now().millisecondsSinceEpoch;
  group('Monitor builder to command to builder to command round trip tests',
      () {
    test('no params', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder();
      String c1 = b1.buildCommand();
      expect(c1, 'monitor\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('empty regex', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()..regex = '    \n \t';
      expect(b1.regex, null);
      String c1 = b1.buildCommand();
      expect(c1, 'monitor\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('just regex', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()..regex = r'\.wavi';
      String c1 = b1.buildCommand();
      expect(c1, 'monitor \\.wavi\n');
      expect(
          c1,
          r'monitor \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('just lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:$nowEpochMillis\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('both regex and lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..regex = r'\.wavi'
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:$nowEpochMillis \\.wavi\n');
      expect(
          c1,
          r'monitor:'
          '$nowEpochMillis'
          r' \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('just strict', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()..strict = true;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('just multiplexed', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()..multiplexed = true;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:multiplexed\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('just self notifications', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..selfNotificationsEnabled = true;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:selfNotifications\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict and regex', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..regex = r'\.wavi';
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict \\.wavi\n');
      expect(
          c1,
          r'monitor:strict \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('multiplexed and regex', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..multiplexed = true
        ..regex = r'\.wavi';
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:multiplexed \\.wavi\n');
      expect(
          c1,
          r'monitor:multiplexed \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict and lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict:$nowEpochMillis\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('multiplexed and lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..multiplexed = true
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:multiplexed:$nowEpochMillis\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict, multiplexed and regex', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..multiplexed = true
        ..regex = r'\.wavi';
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict:multiplexed \\.wavi\n');
      expect(
          c1,
          r'monitor:strict:multiplexed \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict, multiplexed and lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..multiplexed = true
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict:multiplexed:$nowEpochMillis\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict, self notifications , multiplexed and lastNotificationTime',
        () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..selfNotificationsEnabled = true
        ..multiplexed = true
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(
          c1, 'monitor:strict:selfNotifications:multiplexed:$nowEpochMillis\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
    test('strict, multiplexed, regex and lastNotificationTime', () {
      MonitorVerbBuilder b1 = MonitorVerbBuilder()
        ..strict = true
        ..multiplexed = true
        ..regex = r'\.wavi'
        ..lastNotificationTime = nowEpochMillis;
      String c1 = b1.buildCommand();
      expect(c1, 'monitor:strict:multiplexed:$nowEpochMillis \\.wavi\n');
      expect(
          c1,
          r'monitor:strict:multiplexed'
          ':$nowEpochMillis'
          r' \.wavi'
          '\n');
      MonitorVerbBuilder b2 = MonitorVerbBuilder.getBuilder(c1.trim());
      expect(b2, b1);
      String c2 = b2.buildCommand();
      expect(c2, c1);
    });
  });
}
