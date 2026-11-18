Feature: tool/serve.dart serves the built harness on localhost

  serve builds the dev harness and serves build/ on IPv4 and IPv6 loopback.
  Every response is Cache-Control: no-store.

  Scenario: serve serves a file with its content type
    Given a build directory holding html, js, mjs and wasm files
    When each is requested
    Then it is served with its own content type, wasm as application/wasm

  Scenario: serves index.html at the root
    Given a build directory with an index.html
    When / is requested
    Then index.html is served

  Scenario: refuses an encoded separator that would climb out of the root
    Given a file outside the build directory
    When a path with an encoded slash or backslash between dot segments is requested
    Then the answer is 403 and the file is not served

  Scenario: never serves a file above the root for encoded dot segments
    Given a file outside the build directory
    When a path of encoded dot segments is requested
    Then the answer is 403 or 404 and the file is not served

  Scenario: serve.dart accepts a port from 0 to 65535
    Given a --port value from 0 to 65535
    When serve.dart reads it
    Then it listens on that port, 0 picking a free one

  Scenario: serve.dart rejects a port outside 0-65535 naming the value
    Given a --port value above 65535 or below 0
    When serve.dart reads it
    Then it exits 64 with "--port: must be 0-65535, got" and the value
