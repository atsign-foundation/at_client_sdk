Feature: The bridge builds one declared compile target

  packages/at_client_web/tool/build.sh builds the bridge entry for one compile
  target, dart2js or dart2wasm, and writes the bridge manifest with every
  build. With no arguments it keeps today's behaviour: both entries, dart2js
  plus a best-effort dart2wasm. The scenarios run the script with a stub dart
  first on PATH, so they need no real compile and no network.

  Scenario: dart2js target builds only the js file
    Given a build directory that holds an earlier wasm module and loader
    When the bridge entry is built with --target dart2js or --target=dart2js
    Then it exits 0 and build holds at_client_web.js only
    And no at_client_web.wasm or at_client_web.mjs remains

  Scenario: dart2wasm target builds the wasm module and its loader
    Given a build directory that holds an earlier js file
    When the bridge entry is built with --target dart2wasm
    Then it exits 0 and build holds at_client_web.wasm, at_client_web.mjs and bridge-manifest.json
    And no at_client_web.js remains

  Scenario: dart2wasm target forces WASM_REQUIRED on
    Given WASM_REQUIRED is unset or set to 0
    When the bridge entry is built with --target dart2wasm
    Then the compiler is run with WASM_REQUIRED set to 1

  Scenario: A dart2wasm compile failure exits 1 for the wasm target
    Given a dart whose wasm compile fails, with WASM_REQUIRED unset or 0
    When the bridge entry is built with --target dart2wasm
    Then it exits 1 and names dart2wasm compile failed

  Scenario: A dart2js build is untouched by a failing dart2wasm
    Given a dart whose wasm compile fails
    When the bridge entry is built with --target dart2js
    Then it exits 0 and builds at_client_web.js without running a wasm compile

  Scenario: No arguments keeps both entries and a best-effort dart2wasm
    Given no build arguments
    When the build runs with a failing wasm compile
    Then it exits 0, prints one dart2wasm warning per entry and keeps both js files
    And when the wasm compile works it also leaves each entry's wasm module and loader

  Scenario: Bad build arguments are refused naming the allowed values
    Given a target of both, an empty target, an unknown target or an unknown entry
    When the build runs
    Then it exits non-zero without compiling
    And the message names dart2js and dart2wasm

  Scenario: A build removes stale js wasm and mjs files of the entry
    Given a build directory that holds a js, a wasm and an mjs file of the entry
    When the entry is built and its compile writes nothing
    Then none of the three files remains

  Scenario: Both targets write the committed manifest bytes
    Given the committed bridge-manifest.json
    When the bridge entry is built for dart2js and for dart2wasm
    Then build/bridge-manifest.json is byte-identical to the committed file for each
    And it was written before the first compile
