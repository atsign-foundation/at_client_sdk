import 'package:at_lookup/src/util/lookup_util.dart';
import 'package:test/test.dart';

void main() {
  group('LookUpUtil.getSecondaryInfo', () {
    test('splits host:port into the host and the port', () {
      expect(LookUpUtil.getSecondaryInfo('vip.ve.atsign.zone:8443'),
          ['vip.ve.atsign.zone', '8443']);
    });

    test('keeps a bracketed IPv6 literal whole, brackets included', () {
      expect(LookUpUtil.getSecondaryInfo('[::1]:8443'), ['[::1]', '8443']);
      expect(LookUpUtil.getSecondaryInfo('[2001:db8::1]:64'),
          ['[2001:db8::1]', '64']);
    });

    test('gives nothing for a url without a port', () {
      expect(LookUpUtil.getSecondaryInfo('vip.ve.atsign.zone'), isEmpty);
    });
  });
}
