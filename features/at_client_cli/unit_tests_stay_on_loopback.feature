Feature: A unit test reaches no atDirectory or atServer off the loopback interface
  A scan in packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart
  reads every Dart file in the unit-test trees of at_client_cli, at_auth,
  at_client and at_client_flutter, and fails when a test could connect to a
  host that is not on the loopback interface, or to root.atsign.org by
  leaving a root unnamed. Each rule below is held by controls that must
  fail when the rule is removed. The scan is a source scan, a tripwire
  against honest mistakes, not a sandbox.

  Races: the scan reads files once, in one process; nothing shared changes.
  Replay: nothing is signed or sent; nothing could be replayed.
  DoS: a bounded read of the test trees, with a floor on the files each tree
  holds so that a moved tree fails the scan rather than emptying it.
  Forgery: a test that spoofs an atDirectory on the loopback interface
  reaches only itself; the scan judges source text, not what answers.
  Impersonation: no credential is held or used by the scan.

  Scenario: A finder or connection factory built for another host is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan judges a root by its whole host, reads a root set by assignment, and catches each spelling of the real verbs
    Given a test builds CacheableSecondaryAddressFinder, SecondaryUrlFinder, HttpsSecondaryAddressFinder, FixedSecondaryAddressFinder or fixedAddressWebSocketLookUps for a host that is not 127.0.0.1 or localhost
    When the scan reads the test
    Then it reports the finder and its host
    And a host that merely begins with 127.0.0.1 or localhost is not accepted

  Scenario: A finder torn off or subclassed is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    Given a test tears off a finder's constructor, or extends a finder
    When the scan reads the test
    Then it reports the finder
    And a type literal or isA<Finder>() is not reported, since it constructs nothing

  Scenario: A test-own SecondaryAddressFinder that answers another host is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    Given a test declares a class implementing or extending SecondaryAddressFinder
    And the class answers SecondaryAddress for a host that is not on the loopback interface
    When the scan reads the test
    Then it reports the class
    And one that answers 127.0.0.1 is not reported

  Scenario: A connection factory torn off, or invoked with no finder, is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps each exemption, and the at_activate rules, to its tree
    Given a test tears off secureSocketLookUps, lookUpsFor, proxyLookUps or webSocketLookUps, or invokes one with no finder
    When the scan reads the test
    Then it reports the factory
    And only the barrel test, which builds each and invokes none, and the rig, which refuses off-loopback roots itself, are exempt
    And a tear-off inside an import or export directive is not reported

  Scenario: A finder argument that may be null is caught, and a spread is read
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    Given a test builds a connection with secondaryAddressFinder null, absent, or a name that may be null
    When the scan reads the test
    Then it reports the connection
    And a finder built or returned by a call, or a name declared as a non-nullable SecondaryAddressFinder, is accepted

  Scenario: An at_activate command line that implicitly onboards against root is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan judges a root by its whole host, reads a root set by assignment, and catches each spelling of the real verbs
    Given a test runs at_activate, CLIBase.fromCommandLineArgs or a runner with a command line that names an atSign, or spreads a list the scan cannot read, and no root
    When the scan reads the test in at_client_cli's own tree
    Then it reports the command line, since the command or the leading option runs against root.atsign.org
    And a spread of a list the file declares is read, and one with a root is accepted
    And the command line an expect call expects is not reported, since it is never run

  Scenario: A root named off the loopback interface, or left to its default, is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan judges a root by its whole host, reads a root set by assignment, and catches each spelling of the real verbs
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps each exemption, and the at_activate rules, to its tree
    Given a test in at_client_cli's own tree names a root by -r, --root-server, rootDomain: or an AtRootDomain call
    Or it uses AtRootDomain.atsignDomain, createAtClient with no rootDomain, or EnrollerSettings on a preference with no root
    When the scan reads the test
    Then it reports the root
    And at_auth, at_client and at_client_flutter tests are not held to the at_activate rules

  Scenario: A command line that asks for help or the version is not held to the root rule
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # auth_cli.dart returns at its help check, and onboard() at its version check, before anything connects
    Given a test runs at_activate with -h, --help or --version anywhere in the command line and no root
    When the scan reads the test
    Then it reports nothing

  Scenario: AtsignFlows is not constructed, subclassed or implemented for real
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan judges a root by its whole host, reads a root set by assignment, and catches each spelling of the real verbs
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps each exemption, and the at_activate rules, to its tree
    Given a test constructs, tears off, or extends AtsignFlows, or a class implements it with other interfaces, a mixin or a generic parameter, and is no Mock
    When the scan reads the test
    Then it reports the real verbs
    And only loopback_flows.dart in at_client_flutter may extend AtsignFlows
    And a Mock that implements AtsignFlows, alongside other interfaces, is accepted

  Scenario: A dialog built without its own flows is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan catches each way to another atDirectory, and passes loopback
    Given a test builds PkamDialog, CramDialog or ApkamActivationDialog with no flows argument, or calls its show
    When the scan reads the test
    Then it reports the dialog

  Scenario: The hand-run samples stay apart from the tests
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps the hand-run samples to themselves
    Given a file among at_client's hand-run samples ends in _test.dart
    Or a file outside the samples imports, exports or takes as a part a file among them
    When the scan reads the file
    Then it reports it

  Scenario: A file that takes a sample as a part is caught
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps the hand-run samples to themselves
    Given a test file holds the line part 'samples/remote_lookup.dart';
    When the scan reads it
    Then it reports that it imports the hand-run samples

  Scenario: The rig refuses a root off the loopback interface
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:Given the rig's loopbackLookUps when a connection with no finder is asked for a root off the loopback interface, then it throws StateError
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:Given the rig's loopbackLookUps when a connection with no finder is asked for a proxy root off the loopback interface, then it throws StateError
    Given the rig's loopbackLookUps
    When a connection with no finder is asked for a root, or a proxy: root, off the loopback interface
    Then it throws StateError naming the root and port, before anything connects

  Scenario: The rig builds a connection for a loopback root, with or without proxy:
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:Given the rig's loopbackLookUps when the root is a proxy on the loopback interface, then it builds one
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:Given the rig's loopbackLookUps when the root is on the loopback interface, then it builds one
    Given the rig's loopbackLookUps
    When a connection is asked for 127.0.0.1, or for proxy:127.0.0.1
    Then it builds a connection, which the test closes

  Scenario: Each exemption stays to its own file
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:the scan keeps each exemption, and the at_activate rules, to its tree
    Given at_client's transport helper or hand-run samples hold a finder for another host
    When the scan reads files elsewhere with the same finder
    Then it reports them

  Scenario: No unit test in the four packages reaches off the loopback interface
    # test: packages/at_client_cli/test/unit_tests_stay_on_loopback_test.dart:nothing in a test in any of the four packages reaches an atDirectory off the loopback interface
    Given the test trees of at_client_cli, at_auth, at_client and at_client_flutter
    When the scan reads each Dart file but its own
    Then it reports nothing
    And each tree holds at least its floor of files

