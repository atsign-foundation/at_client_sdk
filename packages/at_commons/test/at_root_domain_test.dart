import 'package:at_commons/at_commons.dart'
    show AtRootDomain, IllegalArgumentException;

import 'package:test/test.dart';

void validParseTest(String input, String expectedRootDomain, int expectedPort) {
  test('Parses "$input" successfully', () {
    var root = AtRootDomain.parse(input);
    expect(root.rootDomain, expectedRootDomain);
    expect(root.rootPort, expectedPort);
  });
}

void invalidParseTest<T>(String input) {
  test('Throws parsing "$input"', () {
    expect(() => AtRootDomain.parse(input), throwsA(TypeMatcher<T>()));
  });
}

void main() {
  group("AtRootDomain - Valid parse", () {
    // Only domain
    validParseTest("root.atsign.org", "root.atsign.org", 64);
    validParseTest("root.atsign.wtf", "root.atsign.wtf", 64);
    validParseTest("vip.ve.atsign.zone", "vip.ve.atsign.zone", 64);
    validParseTest("my.foobar.root", "my.foobar.root", 64);

    // domain:port
    validParseTest("root.atsign.org:64", "root.atsign.org", 64);
    validParseTest("root.atsign.wtf:64", "root.atsign.wtf", 64);
    validParseTest("vip.ve.atsign.zone:64", "vip.ve.atsign.zone", 64);
    validParseTest("my.foobar.root:64", "my.foobar.root", 64);

    // proxy:domain
    validParseTest(
      "proxy:proxy0001.atsign.org",
      "proxy:proxy0001.atsign.org",
      64,
    );
    validParseTest(
      "proxy:my.foobar.proxy",
      "proxy:my.foobar.proxy",
      64,
    );

    // proxy:domain:port
    validParseTest(
      "proxy:proxy0001.atsign.org:64",
      "proxy:proxy0001.atsign.org",
      64,
    );
    validParseTest(
      "proxy:my.foobar.proxy:64",
      "proxy:my.foobar.proxy",
      64,
    );
  });
  group("AtRootDomain - Invalid parse", () {
    invalidParseTest<IllegalArgumentException>("");
    invalidParseTest<IllegalArgumentException>("foo:root.atsign.org");
    invalidParseTest<IllegalArgumentException>("foo:root.atsign.org:64");
    invalidParseTest<IllegalArgumentException>("proxy:root.atsign.org:baz");
    invalidParseTest<IllegalArgumentException>("root.atsign.org:baz");
    invalidParseTest<IllegalArgumentException>("root.atsign.org:0");
    invalidParseTest<IllegalArgumentException>("root.atsign.org:65536");
  });
}
