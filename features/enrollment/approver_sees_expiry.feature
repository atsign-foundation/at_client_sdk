Feature: An approver app sees the expiry a request asks for

  at_client's Enrollment reports the key expiry an enrollment asked for, as
  apkamKeysExpiryDuration, and when its record expires, as expiresAt, so an
  app can show both before deciding whether to approve. Duration.zero, or a
  negative value, means no expiry was asked for. Null means the atServer did
  not say, which is unknown, never "no expiry", and a value of the wrong
  type reads the same way. at_activate's list shows both, and its fetch
  prints both. A notification announces a request; enroll:fetch is the
  record of what it asks. Approving returns the enrollment as the atServer
  holds it afterwards, with the term the atServer recorded and when the
  enrollment expires.

  Races: approving and reading B afterwards are two commands, so another
  approver can revoke B in between, or B can expire or be deleted. approve
  returns B as it reads it, and throws when the atServer no longer holds it.
  Replay and DoS: nothing new is written, signed or retried; approve adds
  one enroll:list.
  Forgery and impersonation: every value is the approver's own atServer's
  record, read over the approver's authenticated connection. A value of the
  wrong type reads as null. For apkamKeysExpiryDuration that is unknown,
  never "no expiry"; for expiresAt, null is also how a record that never
  expires reads.

  Scenario Outline: An app sees the expiry a pending request asks for
    Given @alice's enrollment B is pending, asking for <requested>
    When an approver app reads B through <api>
    Then B's Enrollment has apkamKeysExpiryDuration <reported>

    Examples:
      | requested | api                                | reported      |
      | 1 hour    | client.enrollments.pending()       | 1 hour        |
      | 1 hour    | client.enrollments.fetch(B)        | 1 hour        |
      | 1 hour    | client.enrollments.requests        | 1 hour        |
      | no expiry | client.enrollments.pending()       | Duration.zero |

  Scenario: An atServer that does not report the requested expiry
    Given an atServer whose enroll:list entry for B carries no apkamKeysExpiryInMillis
    When an approver app lists B
    Then B's Enrollment has apkamKeysExpiryDuration null

  Scenario Outline: An atServer that serves an expiry of the wrong type
    Given @alice's atServer serves enrollment B with <field> set to <value>
    When an approver app reads B through <api>
    Then B's Enrollment has <property> null, and the rest of B's record reads as served

    Examples:
      | field                   | value                    | api                          | property                |
      | apkamKeysExpiryInMillis | the string "3600000"     | client.enrollments.pending() | apkamKeysExpiryDuration |
      | apkamKeysExpiryInMillis | the number 3600000.5     | client.enrollments.pending() | apkamKeysExpiryDuration |
      | apkamKeysExpiryInMillis | true                     | client.enrollments.fetch(B)  | apkamKeysExpiryDuration |
      | apkamKeysExpiryInMillis | the string "3600000"     | client.enrollments.requests  | apkamKeysExpiryDuration |
      | expiresAt               | the number 1760684400000 | client.enrollments.pending() | expiresAt               |
      | expiresAt               | the string "tomorrow"    | client.enrollments.fetch(B)  | expiresAt               |

  Scenario Outline: The approval returns B as the atServer holds it afterwards
    Given @alice's enrollment B is pending
    And @alice's atServer's record of B, read after the approval, carries <expiresAt>
    When an approver app approves B through client.enrollments.approve(B)
    Then approve returns B with status approved and <reported>

    Examples:
      | expiresAt                                  | reported                                 |
      | expiresAt "2026-10-17T07:00:00.000Z"       | expiresAt 2026-10-17T07:00:00.000Z       |
      | expiresAt "2026-10-17T08:00:00.000+01:00"  | expiresAt 2026-10-17T07:00:00.000Z       |
      | expiresAt null                             | expiresAt null                           |
      | no expiresAt                               | expiresAt null                           |
      | expiresAt 1760684400000, a number          | expiresAt null                           |
      | expiresAt "tomorrow"                       | expiresAt null                           |

  Scenario: The approval returns the term the atServer recorded, not the one asked for
    Given @alice's enrollment B is pending, asking for an expiry of 1 hour
    And @alice's atServer records a 30-minute term for B when it approves it
    When an approver app approves B through client.enrollments.approve(B)
    Then approve returns B with apkamKeysExpiryDuration 30 minutes

  @race
  Scenario: Another approver revokes B between the approval and the read after it
    Given @alice's enrollment B is pending
    And another approver revokes B as soon as it is approved
    When an approver app approves B through client.enrollments.approve(B)
    Then approve returns B with status revoked

  @race
  Scenario: The atServer no longer holds B when it is read after the approval
    Given @alice's enrollment B is pending
    And @alice's atServer holds no record of B once it is approved
    When an approver app approves B through client.enrollments.approve(B)
    Then approve throws AtEnrollmentException, saying B was approved but the atServer no longer holds it

  Scenario: at_activate list shows the expiry each enrollment asked for and when it expires
    Given @alice's enrollment B is pending, asking for an expiry of 1 hour
    When at_activate list runs
    Then B's row shows the 1-hour expiry it asked for and when its record expires

  Scenario: at_activate fetch prints the expiry an enrollment asked for and when it expires
    Given @alice's enrollment B is pending, asking for an expiry of 1 hour
    When at_activate fetch runs for B
    Then the record it prints carries the 1-hour expiry B asked for and when its record expires
