import 'dart:io';

import 'package:test/test.dart';

import '../bin/issuer.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('issuer_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Issuer issuer() => Issuer(
    cramKeys: Issuer.parseCramKeys('alpha\t111\nbravo\t222\n\n'),
    state: File('${dir.path}/state.json'),
    rootDomain: 'vip.ve.atsign.zone:35000',
  );

  test('parses the EE\'s CRAM key file, in order', () {
    expect(Issuer.parseCramKeys('alpha\t111\nbravo 222\n\n'), {
      '@alpha': '111',
      '@bravo': '222',
    });
  });

  test('issues each atSign once, in order, then none', () {
    final i = issuer();

    expect(i.issueNext(), {
      'atSign': '@alpha',
      'cramKey': '111',
      'rootDomain': 'vip.ve.atsign.zone:35000',
    });
    expect(i.issueNext()?['atSign'], '@bravo');
    expect(i.issueNext(), isNull);
  });

  test('never reissues an atSign after a restart', () {
    issuer().issueNext();

    final restarted = issuer();

    expect(restarted.issued, ['@alpha']);
    expect(restarted.issueNext()?['atSign'], '@bravo',
        reason: 'the first issuer\'s state file says @alpha is taken');
  });
}
