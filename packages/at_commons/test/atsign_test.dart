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
