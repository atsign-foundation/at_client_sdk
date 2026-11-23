Feature: Each bridge release publishes one target's files and the manifest

  The workflow at_client_web_bridge_release.yaml builds one declared target,
  dart2js by default or dart2wasm, and attaches that target's files plus
  bridge-manifest.json and one SHA256SUMS to a prerelease, with a build
  provenance attestation. These scenarios read the workflow text and run its
  tag case block; a workflow run itself is not exercised.

  Scenario: Each target tag is fixed by the target
    Given the workflow tag step
    When its case block runs with the dart2js target and with the dart2wasm target
    Then dart2js gives the prefix at_client_web-bridge-
    And dart2wasm gives the prefix at_client_web-bridge-wasm-
    And any other target is refused

  Scenario: One checksum file covers every asset and the manifest
    Given the workflow asset step
    When it lists a target's assets
    Then SHA256SUMS lists that target's files and bridge-manifest.json
    And the release job verifies it with sha256sum -c
    And the dart2js release also keeps at_client_web.js.sha256

  Scenario: Attestation covers the same files as the checksum file
    Given the workflow attest step
    When its subject-path is read
    Then there is exactly one attest step, with subject-path bridge/*
    And it runs after the step that proves bridge/ holds exactly the target's assets, bridge-manifest.json and SHA256SUMS

  Scenario: The release build compares its manifest with the committed one
    Given the workflow build step
    When the bridge is built for the target
    Then cmp compares build/bridge-manifest.json with the committed file after the build
    And bridge-manifest.json is bundled, attested and attached for both targets
