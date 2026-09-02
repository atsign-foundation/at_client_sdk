# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

Feature: A1 · Onboard a new atSign (PQ-native)
  A first enrollment activates an atSign with CRAM and comes up post-quantum:
  a PQ authentication key, a signing root the atSign owns, and a key package
  other enrollments can seal to. Legacy material is still cut and published by
  default, because whether this atSign will ever need it is decided by the apps
  that adopt it, not here.

  Background:
    Given "@alice"'s atServer is PQ-capable

  # acceptance.md section 2 UC-A1.1
  @UC-A1.1 @live @happy
  Scenario: A first-enrollment CRAM onboard is PQ-native and still legacy-reachable
    Given "@alice" is unactivated and holds no keys
    And "alice1" holds "@alice"'s CRAM activation secret
    When "alice1" onboards "@alice" with CRAM
    Then "alice1" authenticates with a PQ APKAM key
    And "alice1" holds no RSA APKAM key
    And "@alice"'s signing root is published
    And "@alice"'s signing root is mutable
    And a second create of "@alice"'s root mint lock is refused by the atServer
    And "alice1" holds the signing root's private half
    And a sender asked to encapsulate to "@alice"'s signing root is refused
    And "alice1"'s key package is registered on its enrollment record
    And "alice1"'s key package is not published
    And "alice1"'s key package is discoverable only by an entitled enrollment
    And "@alice" holds a self encryption key
    And a self write by "alice1" does not use the self encryption key
    And "@alice"'s legacy public encryption key is published

  # acceptance.md section 2 UC-A1.1, last clause — the opt-out arm, against the default above as control
  @UC-A1.1 @live @negative @control
  Scenario: With legacy material opted out, no legacy public key is published
    Given "@alice" is unactivated and holds no keys
    And "alice1" holds "@alice"'s CRAM activation secret
    And "alice1" opts out of legacy key material
    When "alice1" onboards "@alice" with CRAM
    Then "@alice" holds no legacy encryption keypair
    And "@alice"'s legacy public encryption key is not published
