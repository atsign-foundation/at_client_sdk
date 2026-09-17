import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

/// `Atsign(String)` and `toAtsign()` are one route: whatever one accepts,
/// normalises or refuses, the other does identically.
void main() {
  test('the constructor normalises exactly as toAtsign does', () {
    for (final spelling in ['@alice', 'alice', 'Alice', '@Colin.Constable']) {
      expect(Atsign(spelling), spelling.toAtsign(),
          reason: '"$spelling": the two routes must agree');
    }
    expect(Atsign('Alice'), '@alice');
    expect(Atsign('@Colin.Constable'), '@colinconstable',
        reason: 'lower-cased, and the dots in the name removed');
  });

  test('the constructor refuses exactly what toAtsign refuses', () {
    for (final invalid in ['', '@', 'ali ce', 'al@ice', 'alice!']) {
      expect(() => Atsign(invalid), throwsA(isA<InvalidAtSignException>()),
          reason: '"$invalid"');
      expect(() => invalid.toAtsign(), throwsA(isA<InvalidAtSignException>()),
          reason: '"$invalid": the control, the route the constructor mirrors');
    }
  });
}
