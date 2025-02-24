import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  test('Test atSignPKChangedEvent toJson', () {
    AtSignPKChangedEvent e = AtSignPKChangedEvent('@alice');
    expect(e.toJson(), {
      'category': AtServerEvent.atProtocolCategory,
      'name': AtServerEvent.atSignPKChangedEventName,
      'data': {'atSign': '@alice'}
    });
  });

  test('Test atSignPKChangedEvent fromJson', () {
    AtSignPKChangedEvent e1 = AtSignPKChangedEvent('@alice');
    AtSignPKChangedEvent e2 = AtSignPKChangedEvent.fromJson(e1.toJson());
    expect(e2.toJson(), e1.toJson());
    expect(e2.atSign, e1.atSign);
  });

  test('Test atSignPKChangedEvent makes all latin chars lowercase', () {
    final e = AtSignPKChangedEvent('@ALICE');
    expect(e.atSign, '@alice');
  });

  test('Test atSignPKChangedEvent rejects invalid atSigns', () {
    expect(() => AtSignPKChangedEvent('@al@ice'),
        throwsA(isA<InvalidAtSignException>()));
    expect(() => AtSignPKChangedEvent('al@ice'),
        throwsA(isA<InvalidAtSignException>()));
    expect(() => AtSignPKChangedEvent('@@alice'),
        throwsA(isA<InvalidAtSignException>()));
    expect(() => AtSignPKChangedEvent('alice@'),
        throwsA(isA<InvalidAtSignException>()));
    expect(() => AtSignPKChangedEvent('@alice@'),
        throwsA(isA<InvalidAtSignException>()));
  });

  test('Test atSignPKChangedEvent prepends with @ if missing', () {
    final e = AtSignPKChangedEvent('alice');
    expect(e.atSign, '@alice');
  });
}
