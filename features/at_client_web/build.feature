Feature: The build script builds the entries it is asked for

  packages/at_client_web/tool/build.sh builds the browser entries into build/.
  With no argument it builds both entries with dart2js and dart2wasm; with
  at_client_bridge_entry it builds only build/at_client_web.js; any other
  argument is refused.

  Scenario: build.sh with no argument builds both entries
    Given tool/build.sh run with no argument and a dart that records its arguments
    When it finishes
    Then dart compile js ran for web/at_client_web_entry.dart and web/at_client_bridge_entry.dart
    And dart compile wasm was attempted for both

  Scenario: build.sh with at_client_bridge_entry builds only the bridge with dart2js
    Given tool/build.sh run with the argument at_client_bridge_entry and a dart that records its arguments
    When it finishes
    Then dart compile js ran once, for web/at_client_bridge_entry.dart, writing build/at_client_web.js
    And dart compile wasm never ran

  Scenario: build.sh with any other argument is refused
    Given tool/build.sh run with the argument bogus
    When it finishes
    Then it exits 1 and writes "unknown entry 'bogus'" to stderr
    And no compile ran
