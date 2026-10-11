import 'package:at_commons/at_commons.dart';
import 'package:test/test.dart';

void main() {
  group("Validating Atsign type: ", () {
    test("All strings should remain the same as an Atsign", () {
      String alice = "@alice";
      String bob = "@bob_bobert";
      String colin = "@colin123";

      Atsign realAlice = alice.toAtsign();
      Atsign realBob = bob.toAtsign();
      Atsign realColin = colin.toAtsign();

      expect(realAlice, alice);
      expect(realBob, bob);
      expect(realColin, colin);
    });

    test("All atSigns should be fixed", () {
      // @signs are always lowercase
      String brokenAlice = "@ALICE";
      // prepend "@" if missing
      String brokenBob = "bob";
      // both of the above
      String brokenColin = "COLIN";
      // The dot "." can be used in an @sign but it is removed so @colinconstable is the same as @colin.constable
      // home.phone@colin stays home.phone@colin
      // but home.phone@colin.constable gets translated to home.phone@colinconstable
      // This is for clarity for humans
      String brokenDave = "@dave.davert";
      expect(brokenAlice.toAtsign(), "@alice");
      expect(brokenBob.toAtsign(), "@bob");
      expect(brokenColin.toAtsign(), "@colin");
      expect(brokenDave.toAtsign(), "@davedavert");
    });

    test("All atsigns should throw an exception", () {
      String empty = "";
      String alice = "@@alice";
      String bob = "home.phone@";
      String colin = "@c!;";
      String dave = "@da ve";
      expect(() => empty.toAtsign(), throwsA(isA<InvalidAtSignException>()));
      expect(() => alice.toAtsign(), throwsA(isA<InvalidAtSignException>()));
      expect(() => bob.toAtsign(), throwsA(isA<InvalidAtSignException>()));
      expect(() => colin.toAtsign(), throwsA(isA<InvalidAtSignException>()));
      expect(() => dave.toAtsign(), throwsA(isA<InvalidAtSignException>()));
    });
  });

  group("Given an atSign's length", () {
    const String tooLong =
        'invalid @sign: must have at most 55 characters after the @';

    test(
        'when an atSign has 55 characters after its "@", then toAtsign accepts it',
        () {
      final String atSign = '@${'a' * 55}';
      expect(atSign.toAtsign(), atSign);
    });

    test(
        'when an atSign has 56 characters after its "@", then toAtsign throws'
        ' InvalidAtSignException saying it must have at most 55 characters'
        ' after the @', () {
      expect(
          () => '@${'a' * 56}'.toAtsign(),
          throwsA(isA<InvalidAtSignException>()
              .having((e) => e.message, 'message', tooLong)));
    });

    test(
        "when an atSign's dots take it past 55 characters, then toAtsign"
        ' counts it without them', () {
      final String dotted = '@${List.filled(55, 'a').join('.')}';
      expect(dotted.length, greaterThan(56),
          reason: 'the dots alone carry it past the limit');
      expect(dotted.toAtsign(), '@${'a' * 55}');
    });

    test(
        'when an atSign has 55 emoji after its "@", then toAtsign accepts it,'
        ' counting each emoji once', () {
      final String atSign = '@${'\u{1F6E0}' * 55}';
      expect(atSign.length, 111,
          reason: 'each emoji is two UTF-16 code units, so a count of code'
              ' units would refuse it');
      expect(atSign.toAtsign(), atSign);
    });

    test(
        'when Atsign is constructed with 56 characters after its "@", then it'
        ' throws as toAtsign does', () {
      expect(
          () => Atsign('@${'a' * 56}'),
          throwsA(isA<InvalidAtSignException>()
              .having((e) => e.message, 'message', tooLong)));
    });
  });

  group("downstream usage from noports_core/at_server:", () {
    test("noports_core & at_server", () {
      //legacy used to be:
      //typedef Atsign = String;
      // ie: Atsign alice = "alice";
      Atsign alice = "@alice".toAtsign();
      expect(alice, isA<String>());
      String modified = alice + "lebron";
      expect(modified, isA<String>());
      expect(modified, "@alicelebron");
    });
  });
}
