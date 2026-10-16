Feature: An approver app sees the expiry a request asks for

  at_client's Enrollment reports the key expiry an enrollment asked for, as
  apkamKeysExpiryDuration, and when its record expires, as expiresAt, so an
  app can show both before deciding whether to approve. Duration.zero, or a
  negative value, means no expiry was asked for. Null means the atServer did
  not say, which is unknown, never "no expiry". at_activate's list shows
  both, and its fetch prints both. A notification announces a request;
  enroll:fetch is the record of what it asks.

  Races, replay and DoS: these are reads of what the atServer already
  serves; nothing is written, signed or retried.
  Forgery and impersonation: an approver decides on what enroll:fetch
  returns, the atSign's own atServer's record of the request, read over the
  approver's authenticated connection.

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

  Scenario: at_activate list shows the expiry each enrollment asked for and when it expires
    Given @alice's enrollment B is pending, asking for an expiry of 1 hour
    When at_activate list runs
    Then B's row shows the 1-hour expiry it asked for and when its record expires

  Scenario: at_activate fetch prints the expiry an enrollment asked for and when it expires
    Given @alice's enrollment B is pending, asking for an expiry of 1 hour
    When at_activate fetch runs for B
    Then the record it prints carries the 1-hour expiry B asked for and when its record expires
