import 'package:at_client/src/client/durable_address_finder.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// A finder whose next answers are scripted: an address, or a throw.
class _ScriptedFinder implements SecondaryAddressFinder {
  final List<Object> script = [];
  final List<String> asked = [];

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
      {Duration? timeout}) async {
    asked.add(atSign);
    final next = script.removeAt(0);
    if (next is SecondaryAddress) return next;
    throw next;
  }
}

/// `DurableSecondaryAddressFinder`: the atDirectory's answer for the
/// client's own atSign is remembered, and served back when the atDirectory
/// cannot be reached.
void main() {
  const atSign = '@alice';
  late _ScriptedFinder inner;
  late String? slot;
  late int writes;

  DurableSecondaryAddressFinder finder() => DurableSecondaryAddressFinder(
        atSign,
        inner: () => inner,
        read: () async => slot,
        write: (record) async {
          slot = record;
          writes++;
        },
      );

  setUp(() {
    inner = _ScriptedFinder();
    slot = null;
    writes = 0;
  });

  test('the atDirectory\'s answer is remembered, once per address', () async {
    inner.script.addAll([
      SecondaryAddress('a.example', 1),
      SecondaryAddress('a.example', 1),
      SecondaryAddress('b.example', 2),
    ]);
    final f = finder();

    expect((await f.findSecondary(atSign)).toString(), 'a.example:1');
    expect(DurableSecondaryAddressFinder.addressIn(slot).toString(),
        'a.example:1');
    await f.findSecondary(atSign);
    expect(writes, 1, reason: 'the same address is not written twice');
    await f.findSecondary(atSign);
    expect(
        DurableSecondaryAddressFinder.addressIn(slot).toString(), 'b.example:2',
        reason: 'a moved atServer replaces the record');
    expect(writes, 2);
  });

  test('an unreachable atDirectory is answered from the remembered address',
      () async {
    slot = DurableSecondaryAddressFinder.recordFor(
        SecondaryAddress('kept.example', 7));
    inner.script.addAll([
      RootServerConnectivityException('atDirectory down'),
      AtTimeoutException('findAtServer timed out'),
    ]);
    final f = finder();

    expect((await f.findSecondary(atSign)).toString(), 'kept.example:7',
        reason: 'a connectivity failure is the outage this exists for');
    expect((await f.findSecondary(atSign)).toString(), 'kept.example:7',
        reason: 'so is a timeout');
    expect(writes, 0, reason: 'a served-back address is not re-written');
  });

  test('the atDirectory saying there is no atServer is not masked', () async {
    slot = DurableSecondaryAddressFinder.recordFor(
        SecondaryAddress('kept.example', 7));
    inner.script.add(SecondaryNotFoundException('no entry for $atSign'));

    await expectLater(() => finder().findSecondary(atSign),
        throwsA(isA<SecondaryNotFoundException>()),
        reason: 'an answer from the atDirectory is not an outage');
  });

  test('with nothing remembered the outage is the caller\'s', () async {
    inner.script.add(RootServerConnectivityException('atDirectory down'));

    await expectLater(() => finder().findSecondary(atSign),
        throwsA(isA<RootServerConnectivityException>()));
  });

  test('another atSign passes straight through and is never remembered',
      () async {
    slot = DurableSecondaryAddressFinder.recordFor(
        SecondaryAddress('kept.example', 7));
    inner.script.addAll([
      SecondaryAddress('bob.example', 3),
      RootServerConnectivityException('atDirectory down'),
    ]);
    final f = finder();

    expect((await f.findSecondary('@bob')).toString(), 'bob.example:3');
    expect(writes, 0, reason: 'only the client\'s own atServer is kept');
    await expectLater(() => f.findSecondary('@bob'),
        throwsA(isA<RootServerConnectivityException>()),
        reason: '@alice\'s remembered address is no answer for @bob');
    expect(inner.asked, ['@bob', '@bob']);
  });

  test('a record that is not one of ours remembers nothing', () {
    expect(DurableSecondaryAddressFinder.addressIn(null), isNull);
    expect(DurableSecondaryAddressFinder.addressIn('not json'), isNull);
    expect(DurableSecondaryAddressFinder.addressIn('{"host":"x"}'), isNull);
    expect(DurableSecondaryAddressFinder.addressIn('{"host":"x","port":"1"}'),
        isNull,
        reason: 'a port that is not an int is not an address');
  });
}
