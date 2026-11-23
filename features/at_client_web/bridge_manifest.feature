Feature: The bridge publishes one manifest generated from its constants

  packages/at_client_web/tool/manifest.dart writes bridge-manifest.json from the
  bridge's Dart constants: the exported surface and the error codes a rejection
  can carry. Every build and release publishes it. These scenarios run the
  generator and read its source; a release run itself is not exercised.

  Scenario: The generator writes the manifest from the constants byte for byte
    Given the exported surface and the two error code constants
    When the generator runs with no arguments
    Then stdout is the committed bridge-manifest.json byte for byte
    And it holds schemaVersion 1, the methods and the error codes taken from the constants

  Scenario: --out writes the same bytes atomically
    Given a path in an existing directory
    When the generator runs with --out and that path
    Then the file holds the same bytes as the committed manifest
    And nothing is written to stdout
    And no PATH.tmp file remains after the rename

  Scenario: Any other argument is refused naming both forms
    Given the generator
    When it runs with any argument other than --out and a path
    Then it exits 1 and names dart tool/manifest.dart and --out PATH
    And it writes nothing to stdout

  Scenario: The self-check exits 1 on a bad list or an overlap
    Given an error code list or a surface member list that is empty, unsorted or duplicated
    When the generator runs
    Then it exits 1 and names the list
    And the error codes and the collection error codes sharing a code also exit 1
    And no manifest is written

  Scenario: The manifest bytes do not depend on the target
    Given the TARGET environment set to dart2js and then to dart2wasm
    When the generator runs with no arguments
    Then both runs write identical bytes
    And the generator source reads no environment variable

  Scenario: The surface is pinned to the public members of every @JSExport class
    Given the @JSExport classes in lib/src/js/bridge.dart
    When their public members are scanned
    Then they equal the bridgeSurface constant exactly
    And a new exported member or a stale entry fails the comparison
