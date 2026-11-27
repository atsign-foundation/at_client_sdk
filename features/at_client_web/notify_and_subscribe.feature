Feature: notify sends to another atSign and subscribe delivers only genuine events

  notify sends a value on a key shared with another atSign and resolves true
  when it was delivered. subscribe registers when called and calls the event
  callback with each event and returns the function that unsubscribes. A
  notification this session sent, or one whose key owner is not its sender, is
  never delivered.

  These scenarios describe the Dart bridge that @atsign/at_client_web wraps; the
  npm package turns {code, message} into AtError and the callbacks into async
  iterators, and specifies that in at_js.

  # Threats. Each answer names the scenario that holds it.
  #
  # Race: an echo arriving before notify returns is still suppressed ("drops an
  #   echo that arrives before notify resolves"), and one arriving before the
  #   send has reported the id is suppressed too ("an echo that arrives before
  #   the send completes is not delivered"); a notify interrupted by close
  #   while polling rejects closed ("notify interrupted by close rejects with
  #   closed"), and subscribe stops delivering once close starts and cancels if
  #   closed during startListening ("close stops delivering subscription events
  #   and errors even if the stream emits before cancel settles", "subscribe
  #   cancels immediately if close occurs during startListening", "bridge
  #   subscribe drops notifications and errors after session is closed").
  # Replay: the last 1024 sent notification ids are remembered for the session's
  #   own atSign and failed sends do not evict live ids ("remembers only the last
  #   1024 sent ids", "failed notify does not evict sent echo ids"); an
  #   unconfirmed send keeps its id, so a late echo of it is dropped ("a notify
  #   still queued after thirty seconds resolves false and keeps its id").
  # DoS: invalid keys, invalid regexes, and non-function callbacks are refused
  #   before sending or subscribing ("notify with empty or invalid key or
  #   invalid sharedWith rejects with bad_key and sends nothing", "bridge
  #   notify takes key text and refuses a non-string key", "subscribe
  #   with invalid regex rejects naming regex", "subscribe with non-function
  #   callback returns {code: invalid_argument} without throwing"), a
  #   notification key longer than 255 UTF-16 units is dropped before it is
  #   parsed ("a notification key longer than 255 characters is dropped with a
  #   warning"), the envelope's peer-chosen id and key are bounded, so
  #   neither can carry unbounded text into JS ("a peer-chosen notification id
  #   and key are bounded in the envelope"), and the prune bounds the sent
  #   set even when every poll throws ("a notify whose final-status poll
  #   throws after its send keeps its id within the bound"), and a
  #   subscribe or collection watch callback that throws is logged instead of
  #   escaping, so one bad callback cannot stop delivery ("a subscribe callback
  #   that throws is logged and delivery continues", "a collection watch
  #   callback that throws is logged and delivery continues").
  # Forgery: malformed notification keys (multiple @, bare @name.ns, cached:
  #   without recipient, wrong sharedWith, injected text keys) and mismatched
  #   sender/key owner are dropped ("delivers only a notification sent by the
  #   key owner", "subscribe drops notifications with malformed keys or wrong
  #   sharedWith"), and a key holding a bidirectional control character is
  #   dropped before delivery ("a notification key holding bidi controls is
  #   dropped with a warning"). An echo carrying this session's own id cannot
  #   be made deliverable by arriving before the send reports it ("an echo that
  #   arrives before the send completes is not delivered").
  #   Outbound key text cannot widen a key: it carries its own recipient,
  #   owner and namespace, parsed once, and the text's namespace is what is
  #   sent, never the session's ("notify sends the key text's namespace, not
  #   the session's").
  # Impersonation: outbound notify refuses a mismatched owner, a public or
  #   cached key, a recipient not written with @, and text the parsers refuse,
  #   before any lookup, and inbound notifications compare canonical sender and
  #   owner, delivering that canonical owner as sharedBy ("notify with
  #   mismatched sharedBy rejects with bad_key and sends nothing", "notify with
  #   public or cached flag rejects with bad_key and sends nothing", "notify
  #   with empty or invalid key or invalid sharedWith rejects with bad_key and
  #   sends nothing", "matches the sender and the key owner by canonical
  #   atSign", "key parts name the canonical owner for a dotted owner
  #   spelling").

  Scenario: notify resolves true when delivered and false when not
    Given an open session and a recipient
    When notify is called on a key shared with the recipient
    Then it resolves true when the notification was delivered
    And it resolves false when it was not

  Scenario: without sharedWith it is a bad key and sends nothing
    Given an open session
    When notify is called on key text with no recipient
    Then it fails with a bad key
    And nothing is sent to the atServer

  Scenario: notify with mismatched sharedBy rejects with bad_key and sends nothing
    Given an open session as @alice
    When notify is called on key text whose owner is @carol
    Then it rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify with public or cached flag rejects with bad_key and sends nothing
    Given an open session
    When notify is called on public: or cached: key text
    Then each rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify with empty or invalid key or invalid sharedWith rejects with bad_key and sends nothing
    Given an open session
    When notify is called on empty or malformed key text, text with an invalid recipient or one not written with @, or a key name with an empty segment
    Then each rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify sends the key text's namespace, not the session's
    Given an open session in namespace wavi, as @alice
    When notify is called on @bob:k.other@alice and then on @bob:k@alice
    Then the notified keys are @bob:k.other@alice and @bob:k@alice
    And the session namespace is not applied

  Scenario: bridge notify takes key text and refuses a non-string key
    Given an open bridge session
    When notify is called with an object, a number or an array as the key
    Then each rejects with bad_key naming key
    And the session receives nothing

  Scenario: notify interrupted by close rejects with closed
    Given an open session with an in-flight undelivered notify
    When close is called before notify completes
    Then notify rejects with closed

  Scenario: failed notify does not evict sent echo ids
    Given an open session that sent 1024 notifications followed by failed notify calls
    When the atServer delivers the echo of the first sent notification
    Then the subscription still drops that echo

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

  @race @forgery
  Scenario: an echo that arrives before the send completes is not delivered
    Given a subscription and a notify whose echo arrives before the send reports its id
    When the echo of that notification arrives
    Then the subscription does not deliver it

  Scenario: a notify still queued after thirty seconds resolves false and keeps its id
    Given a session whose final-status wait runs out with the notification still queued
    When notify sends a valid key and the echo of that notification later arrives
    Then notify resolves false and the subscription does not deliver the echo

  Scenario: an undelivered notify forgets the id remembered before the send
    Given a subscription and a notify whose id is remembered before the send
    When the notification comes back undelivered
    Then the id is dropped during the send and delivered after the result

  @dos
  Scenario: a notify whose final-status poll throws after its send keeps its id within the bound
    Given a session whose notification service throws a timeout while it reads the final status of every send
    When notify sends 1100 notifications and their echoes and a notification from another sender arrive
    Then the latest send's echo is dropped, the oldest send's id has been pruned, and the other sender's notification is delivered

  Scenario: a notify that never reached the atServer forgets its id when its poll throws
    Given a session whose notification service fails the send and then throws while it reads the final status
    When notify sends a valid key
    Then it rejects and a later echo of that id is delivered

  Scenario: a send that failed is a send failure even when its status wait ran out
    Given a session whose notification service fails the send and whose status wait runs out queued
    When notify sends a valid key
    Then it rejects with send_failed and the id is forgotten

  Scenario: a connection lost during the final-status poll rejects offline
    Given a session whose notification service throws a lost-connection failure while it reads the final status
    When notify sends a valid key
    Then it rejects with offline

  Scenario: a notify refused as unauthorised is not reported offline
    Given a session whose notification service throws an unauthorised failure while it reads the final status
    When notify sends a valid key
    Then the failure reaches the caller as at_client raised it, not as offline

  Scenario: remembers only the last 1024 sent ids
    Given a session that has sent 1025 notifications
    When the atServer delivers notifications for the first, second and last sent ids
    Then only the first, whose id has been forgotten, is delivered

  Scenario: delivers only a notification sent by the key owner
    Given a subscription on every key
    When a notification arrives from an atSign that is not the key's owner
    Then it is not delivered
    And a notification from the key's owner is

  Scenario: sanitizes control and bidi characters in dropped notification logs
    Given a subscription that drops a notification whose id holds a line break and bidirectional formatting characters
    When the warning for the drop is logged
    Then the warning is one line and shows those characters as \u escapes

  Scenario: matches the sender and the key owner by canonical atSign
    Given a subscription on every key
    When notifications arrive whose sender and key owner differ only in case, spacing or a missing @
    Then they are delivered with from as the canonical atSign
    And a notification with no key owner is not delivered

  Scenario: a delivered notification carries its parsed key parts
    Given a subscription on every key
    When a notification arrives with the key @alice:note.wavi@bob from @bob
    Then it is delivered with its name, namespace, recipient, owner, public and cached parts

  @impersonation
  Scenario: key parts name the canonical owner for a dotted owner spelling
    Given a subscription on every key
    When a notification arrives with the key @alice:note.wavi@bob.smith from @bobsmith
    Then its parts carry sharedBy @bobsmith, the same atSign as from

  Scenario: a key without a namespace has a null namespace in its parts
    Given a subscription on every key
    When a notification arrives with the key @alice:attalk@bob
    Then its parts carry a null namespace

  Scenario: a 248-character notification key is delivered whole
    Given a subscription on every key
    When a notification arrives with a 248-character key
    Then it is delivered with that whole key

  @dos
  Scenario: a notification key longer than 255 characters is dropped with a warning
    Given a subscription on every key
    When a 255-character cached key and a 256-character key arrive
    Then the 255-character key is delivered and the 256-character key is dropped with a warning

  Scenario: a 250-character key without cached is delivered whole
    Given a subscription on every key
    When a notification arrives with a 250-character key that is not cached
    Then it is delivered with that whole key

  @forgery
  Scenario: a notification key holding bidi controls is dropped with a warning
    Given a subscription on every key
    When a notification arrives whose key holds a bidirectional control character
    Then it is dropped with a warning
    # General format characters such as U+200B are not in scope: a key holding one is still delivered.

  Scenario: a notification key holding a space or a no-break space is still dropped
    Given a subscription on every key
    When a notification arrives whose key holds a space or a no-break space
    Then it is dropped

  Scenario: a key dropped for length or control text is logged as such, not as a sender mismatch
    Given a subscription on every key
    When a notification arrives whose key is too long or holds control text
    Then the warning names the key, not the sender

  Scenario: the envelope carries the whole key and its parts
    Given a bridge subscription on every key
    When a notification arrives with a 248-character key
    Then the envelope's key is that whole key and keyParts carries its six parts

  Scenario: subscribe drops notifications with malformed keys or wrong sharedWith
    Given a subscription on every key
    When notifications arrive with multiple @s, a bare @name.ns key, cached: without recipient, wrong sharedWith, or injected text keys
    Then none of them is delivered

  Scenario: subscribe with invalid regex rejects naming regex
    Given an open session
    When subscribe is called with an invalid regular expression
    Then it returns {code: invalid_argument} naming regex without starting the monitor

  Scenario: subscribe with non-function callback returns {code: invalid_argument} without throwing
    Given an open session
    When subscribe is called with a non-function callback or a non-function onError
    Then it returns {code: invalid_argument} naming that parameter without throwing

  Scenario: subscribe errors go to onError as {code, message}
    Given a subscription with an onError function
    When the session reports a subscription error that no code maps
    Then onError receives {code: internal, message: 'internal error'}

  Scenario: a stream error reaches onError and the subscription survives
    Given a subscription with an onError function
    When the notification stream reports an error and then a notification
    Then onError receives the error
    And the notification is still delivered

  Scenario: subscribe with no onError does not throw
    Given a subscription with no onError
    When the session reports a subscription error
    Then nothing is thrown

  Scenario: a subscribe callback that throws is logged and delivery continues
    Given a subscription whose onEvent throws
    When two notifications arrive
    Then both are attempted, each throw is logged, and nothing escapes the zone

  Scenario: a collection watch callback that throws is logged and delivery continues
    Given a collection watch whose onEvent throws
    When two collection events arrive
    Then both are attempted, each throw is logged, and nothing escapes the zone

  Scenario: close stops delivering subscription events and errors even if the stream emits before cancel settles
    Given an active subscription whose stream emits an event or error after close starts
    When close is called
    Then neither onEvent nor onError receives post-close deliveries

  Scenario: a subscription whose stream completes is removed
    Given an active subscription
    When its notification stream completes
    Then the session no longer holds that subscription

  Scenario: warns when the subscription of a failed start fails to cancel
    Given a subscription whose start fails and whose cancel then throws
    When close is called
    Then the failure is logged and close still completes

  Scenario: subscribe cancels immediately if close occurs during startListening
    Given an open session whose startListening triggers close synchronously
    When subscribe is called
    Then the subscription is cancelled immediately without leaking into active subscriptions

  Scenario: bridge subscribe drops notifications and errors after session is closed
    Given a BridgeSession subscription and a session marked closed
    When the underlying session emits a notification or error
    Then neither the JS event callback nor the JS error callback is invoked

  @dos @forgery
  Scenario: a peer-chosen notification id and key are bounded in the envelope
    Given a subscription on every key
    When a notification arrives from a session fake whose id and key carry a newline, a direction character and 600 characters
    Then the id comes back on one line at most the rejection bound long
    And the key and each of its parts come back on one line at most the notification key bound long
    And its from, value, epochMillis and operation are unchanged

  Scenario: a send at_client reports failed is a send failure
    Given a session whose notification service reports a failed send, wrapped as at_client wraps it
    When notify sends a valid key
    Then it rejects with notify_failed carrying the send-failed kind

  Scenario: a notify that cannot reach the atServer is an offline failure, or a timeout when it does not answer
    Given a session whose notification service throws a connection failure, or a timeout, while it reads the final status
    When notify sends a valid key
    Then it rejects with offline for the connection failure and timeout for the timeout

  Scenario: a failure where an atServer answered is not an offline failure
    Given a session whose notification service throws an unauthorized, unauthenticated or no-atServer failure
    When notify sends a valid key
    Then the failure reaches the caller as at_client raised it

  Scenario: a notify failure is worded from its kind, never from at_client text
    Given a notify failure of each kind
    When the bridge writes the message JS sees
    Then the wording names the kind and never repeats text at_client wrote

  Scenario: resolves false when the notification is not delivered
    Given a session whose notification service reports the notification was not delivered
    When notify sends a valid key
    Then it resolves false and does not throw
