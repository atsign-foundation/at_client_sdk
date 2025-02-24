import 'package:at_commons/src/atserver/atserver_events.dart';
import 'package:test/test.dart';

void main() {
  test('Test atSignPKChangedEvent toJson', () {
    AtSignPKChangedEvent e = AtSignPKChangedEvent('@alice');
    expect(e.toJson(), {
      'category': AtServerEvent.atProtocolCategory,
      'name': AtServerEvent.atSignPKChangedEventName,
      'data': {
        'atSign': '@alice'
      }
    });
  });
  test('Test atSignPKChangedEvent fromJson', () {
    AtSignPKChangedEvent e1 = AtSignPKChangedEvent('@alice');
    AtSignPKChangedEvent e2 = AtSignPKChangedEvent.fromJson(e1.toJson());
    expect(e2.toJson(), e1.toJson());
    expect(e2.atSign, e1.atSign);
  });
}
