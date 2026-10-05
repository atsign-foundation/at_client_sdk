import 'package:at_client/at_client.dart';
import 'package:at_client/src/crypto/nskey/current_ck_pointer.dart';
import 'package:at_client/src/transformer/request_transformer/put_request_transformer.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'test_utils/mocks.dart';

void main() {
  const alice = '@alice';
  const enrollmentId = 'enr-1';
  const namespace = 'app_1.my_apps';

  setUpAll(() {
    registerFallbackValue(AtKey());
    registerFallbackValue(PutRequestOptions());
    registerFallbackValue(GetRequestOptions());
  });

  /// A client of [alice] authenticated as [enrollmentId], recording every put
  /// with the options it was sent under.
  ({MockAtClient client, List<(AtKey, String, PutRequestOptions?)> puts})
      client({String? enrolledAs = enrollmentId}) {
    final atClient = MockAtClient();
    when(() => atClient.getCurrentAtSign()).thenReturn(alice);
    when(() => atClient.enrollmentId).thenReturn(enrolledAs);
    final puts = <(AtKey, String, PutRequestOptions?)>[];
    when(() => atClient.put(any(), any(),
            putRequestOptions: any(named: 'putRequestOptions')))
        .thenAnswer((inv) async {
      puts.add((
        inv.positionalArguments[0] as AtKey,
        inv.positionalArguments[1] as String,
        inv.namedArguments[#putRequestOptions] as PutRequestOptions?,
      ));
      return true;
    });
    return (client: atClient, puts: puts);
  }

  group('the current-CK pointer', () {
    test('is written in the enrollment\'s own namespace — raw literal',
        () async {
      final c = client();

      await const CurrentCkPointer()
          .write(c.client, '@bob', namespace, 'ck-1', 'nskey-1');

      final (key, value, options) = c.puts.single;
      final command = (await PutRequestTransformer().transform(
              Tuple<AtKey, dynamic>()
                ..one = key
                ..two = value,
              requestOptions: options))
          .buildCommand();
      // NOTE: frozen — the atServer grants each enrollment rw on
      // `<enrollmentId>.a.__e`, refuses it to every other enrollment, and moves
      // it aside on revocation; the record holds ids only, so it goes
      // unencrypted.
      expect(
          command,
          'update:isEncrypted:false:'
          '__ckcur.bob.app_1.my_apps.enr-1.a.__e@alice '
          '{"ckKid":"ck-1","nskeyKid":"nskey-1"}\n');
    });

    test('is written to the atServer first', () async {
      final c = client();

      await const CurrentCkPointer()
          .write(c.client, '@bob', namespace, 'ck-1', 'nskey-1');

      expect(c.puts.single.$3?.useRemoteAtServer, isTrue,
          reason: 'a client whose local storage does not survive a restart '
              'must still find the pointer, and sync reaches the atServer '
              'only when it gets round to it');
    });

    test(
        'is read from the atServer first, and from local storage when the '
        'atServer cannot answer', () async {
      final c = client();
      final routes = <bool?>[];
      when(() => c.client
              .get(any(), getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((inv) async {
        final remote =
            (inv.namedArguments[#getRequestOptions] as GetRequestOptions?)
                ?.useRemoteAtServer;
        routes.add(remote);
        if (remote == true) {
          throw AtClientException.message('the atServer is unreachable');
        }
        return AtValue()..value = '{"ckKid":"ck-1","nskeyKid":"nskey-1"}';
      });

      final read =
          await const CurrentCkPointer().read(c.client, '@bob', namespace);

      expect(read, (ckKid: 'ck-1', nskeyKid: 'nskey-1'));
      expect(routes, [true, false]);
    });

    test('is one read when the atServer answers', () async {
      final c = client();
      final routes = <bool?>[];
      when(() => c.client
              .get(any(), getRequestOptions: any(named: 'getRequestOptions')))
          .thenAnswer((inv) async {
        routes.add(
            (inv.namedArguments[#getRequestOptions] as GetRequestOptions?)
                ?.useRemoteAtServer);
        return AtValue()..value = '{"ckKid":"ck-2","nskeyKid":"nskey-1"}';
      });

      final read =
          await const CurrentCkPointer().read(c.client, '@bob', namespace);

      expect(read, (ckKid: 'ck-2', nskeyKid: 'nskey-1'));
      expect(routes, [true]);
    });

    test('is not kept by a client with no enrollment id', () async {
      final c = client(enrolledAs: null);

      await const CurrentCkPointer()
          .write(c.client, '@bob', namespace, 'ck-1', 'nskey-1');
      final read =
          await const CurrentCkPointer().read(c.client, '@bob', namespace);

      expect(c.puts, isEmpty,
          reason: 'there is no namespace of its own to write it in');
      expect(read, isNull);
      verifyNever(() => c.client
          .get(any(), getRequestOptions: any(named: 'getRequestOptions')));
    });
  });
}
