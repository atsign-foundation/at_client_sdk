# DRAFT from the 2026-09-02 feasibility sample, not a catalogue artefact.
# Translated by hand from docs/projects/pq/acceptance.md to test whether the
# catalogue's rows fit Gherkin; nothing executes these. The clause maps and the
# friction each row exposed are in ../analysis.md section 6.

Feature: Every record says which scheme opens it
  A record's provider id is authoritative: it names every algorithm a reader
  needs code for, so a scheme change rolls out rather than needing a flag day.
  It must be present on stored records, on notification frames and on lookup
  responses, and it must survive every hop that writes a record to the
  atServer — the sync push once dropped it, and every cross-atSign read fell
  back to legacy for every provider, with no error anywhere.

  # acceptance.md section 13 — unnumbered by design; the Examples table IS the raw-literal pin
  @invariant @in-process @live-owed @security
  Scenario Outline: A stored record names its provider, and the name survives the trip to the atServer
    Given "@alice" has a namespace key for "app_1.my_apps"
    When "alice1" writes "treaty" into "app_1.my_apps"
    Then <record> names provider "<provider>"
    And <record> carries <fields>
    And <record> arrives at the atServer with the same provider and fields
    Examples:
      | record                     | provider                | fields                                     |
      | the value "treaty"         | at/symmetric/AES/GCM    | providerId, ckKid, iv                      |
      | the content-key conveyance | at/nskey/XWING/AES/GCM  | providerId, recipientKind, ckKid, nskeyKid |

  @invariant @live @security
  Scenario: A notification frame names its provider too
    Given "@bob" has a namespace key for "app_1.my_apps"
    When "alice1" notifies "@bob" with an encrypted value in "app_1.my_apps"
    Then the frame "@bob" receives names the provider that opens it
    And every enrollment of "@bob" opens it with that provider

  @invariant @in-process @live-exempt
  Scenario: A record with no provider id is opened as legacy
    Given a record stored with no provider id
    When "alice1" reads it
    Then it is opened with the legacy scheme
