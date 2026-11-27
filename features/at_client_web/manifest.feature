Feature: The bridge manifest publishes the sets a keyless conformance test needs

  bridge-manifest.json is generated from the Dart constants and byte-compared
  in the package's tests. Schema 2 adds the options create reads for each
  session form, the fields of the subscribe envelope, every status the session
  reports and the bound the bridge applies to untrusted text. A keyless JS
  conformance test reads them here instead of restating them.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: the manifest is generated from the constants in the same commit and a
  #   byte-compare test fails on any drift, so no half-updated manifest can be
  #   released ("the manifest schema version is 2").
  # Replay: schemaVersion counts released manifests, so a consumer holding a
  #   cached copy can tell which layout it has ("the manifest schema version is
  #   2").
  # DoS: the manifest publishes the bounds every untrusted text and
  #   notification key takes, so a consumer can cap what it shows without
  #   reading the bridge ("the manifest bounds match the bridge constants").
  # Forgery: the create options are scanned from bridge.dart, so the manifest
  #   cannot advertise an option the bridge does not read ("the manifest lists
  #   the create options each session form reads").
  # Impersonation: the manifest lists field names, statuses and a length, never
  #   a peer-supplied identity or credential ("the manifest lists the subscribe
  #   envelope fields").

  Scenario: the manifest lists the create options each session form reads
    Given the options BridgeEntry.create reads
    When the manifest is generated
    Then createOptions names the common options plus each form's own
    And each list is sorted

  Scenario: the manifest lists the subscribe envelope fields
    Given the envelope BridgeSession.subscribe delivers
    When the manifest is generated
    Then envelopes.subscribe names id, from, key, keyParts, value, epochMillis and operation
    And envelopes.keyParts names name, namespace, sharedWith, sharedBy, isPublic and isCached

  Scenario: the manifest lists every connection status
    Given the statuses AtClientSession can report
    When the manifest is generated
    Then statuses is connected, connecting, waiting:auth, waiting:network and waiting:server
    And the fallback the session starts with is among them

  Scenario: the manifest bounds match the bridge constants
    Given the bridge's maximum error message length and maximum notification key length
    When the manifest is generated
    Then bounds.maxErrorMessageLength and bounds.maxNotificationKeyLength equal them rather than copied literals

  Scenario: the manifest schema version is 2
    Given this release adds top-level keys and list entries
    When the manifest is generated
    Then schemaVersion is 2
