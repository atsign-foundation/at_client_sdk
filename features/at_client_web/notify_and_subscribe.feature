Feature: notify sends to another atSign and subscribe delivers only genuine events

  notify sends a value on a key shared with another atSign and resolves true
  when it was delivered. subscribe registers when called and hands the app
  events as an async iterator. A notification this session sent, or one whose
  key owner is not its sender, is never delivered. The iterator buffers up to
  4096 events; past that it ends and its next() rejects overflow.

  Races: an echo that arrives before notify resolves is still dropped; a
  subscribe registers at call time, not at the first next().
  Replay: the session drops the echo of each of its last 1024 sent ids; any
  other notification is delivered as often as the atServer sends it.
  DoS: an app that stops reading is bounded at 4096 buffered events and then
  unsubscribed; the sent-id memory is bounded at 1024.
  Forgery: an event is delivered only when the key owner equals the sender,
  compared as canonical atSigns, so a third atSign cannot name another's key.
  Impersonation: from is the canonical sender atSign, and the session's own
  echoes never reach the app as if another party had sent them.

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

  Scenario: a subscription that buffers past the cap unsubscribes and rejects with overflow
    Given an open subscription the app is not reading
    When 4097 events arrive
    Then the subscription is unsubscribed once
    And next() rejects with AtError code overflow
    And the next next() is done

  Scenario: close ends every open iterator, unsubscribes each and closes the bridge session
    Given two open subscriptions, one with a next() waiting
    When close is called
    Then both iterators finish done
    And each subscription is unsubscribed
    And the bridge session is closed once

  Scenario: subscribe after close throws closed without touching the bridge
    Given a closed client
    When subscribe is called
    Then it throws AtError code closed synchronously
    And the bridge is not asked to subscribe

  Scenario: a failed subscribe surfaces its code as an AtError
    Given a bridge whose subscribe answers with { code: 'closed', message }
    When subscribe is called
    Then it throws an AtError with that code
