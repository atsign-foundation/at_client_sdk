Feature: notify sends to another atSign and subscribe delivers only genuine events

  notify sends a value on a key shared with another atSign and resolves true
  when it was delivered. subscribe registers when called and hands the app
  events as an async iterator. A notification this session sent, or one whose
  key owner is not its sender, is never delivered. The iterator buffers up to
  4096 events; past that it ends and its next() rejects overflow.

  Scenario: notify resolves true when delivered and false when not
    Given an open session and a recipient
    When notify is called on a key shared with the recipient
    Then it resolves true when the notification was delivered
    And it resolves false when it was not

  Scenario: without sharedWith it is a bad key and sends nothing
    Given an open session
    When notify is called on a key with no sharedWith
    Then it fails with a bad key
    And nothing is sent to the atServer

  Scenario: drops the echo of a notification this session sent
    Given a subscription on every key and a notification this session has sent
    When the atServer delivers that notification back
    Then the subscription does not deliver it
    And a notification from the key owner that this session did not send is delivered

  Scenario: delivers a peer notification that reuses an id this session sent
    Given a subscription on every key and a notification this session has sent
    When another atSign's notification arrives carrying that same id
    Then the subscription delivers it with that atSign as from
    And this session's own echo of the id is still dropped

  Scenario: drops an echo that arrives before notify resolves
    Given a subscription and a notify still waiting for the atServer
    When the echo of that notification arrives before notify resolves
    Then the subscription does not deliver it

  Scenario: remembers only the last 1024 sent ids
    Given a session that has sent 1025 notifications
    When the atServer delivers notifications for the first, second and last sent ids
    Then only the first, whose id has been forgotten, is delivered

  Scenario: delivers only a notification sent by the key owner
    Given a subscription on every key
    When a notification arrives from an atSign that is not the key's owner
    Then it is not delivered
    And a notification from the key's owner is

  Scenario: matches the sender and the key owner by canonical atSign
    Given a subscription on every key
    When notifications arrive whose sender and key owner differ only in case, spacing or a missing @
    Then they are delivered with from as the canonical atSign
    And a notification with no key owner is not delivered
