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
  #   echo that arrives before notify resolves"), a notify interrupted by close
  #   while polling rejects closed ("notify interrupted by close rejects with
  #   closed"), and subscribe stops delivering once close starts and cancels if
  #   closed during startListening ("close stops delivering subscription events
  #   and errors even if the stream emits before cancel settles", "subscribe
  #   cancels immediately if close occurs during startListening", "bridge
  #   subscribe drops notifications and errors after session is closed").
  # Replay: the last 1024 sent notification ids are remembered for the session's
  #   own atSign and failed sends do not evict live ids ("remembers only the last
  #   1024 sent ids", "failed notify does not evict sent echo ids").
  # DoS: invalid keys, invalid regexes, and non-function callbacks are refused
  #   before sending or subscribing, and noNamespace skips only the namespace
  #   check, never the key-name check ("notify with noNamespace true still
  #   rejects a key name that carries more key text and sends nothing", "bridge
  #   notify passes noNamespace as given and refuses a non-boolean", "notify with empty or invalid key or
  #   invalid sharedWith rejects with bad_key and sends nothing", "subscribe
  #   with invalid regex rejects naming regex", "subscribe with non-function
  #   callback returns {code: invalid_argument} without throwing").
  # Forgery: malformed notification keys (multiple @, bare @name.ns, cached:
  #   without recipient, wrong sharedWith, injected text keys) and mismatched
  #   sender/key owner are dropped ("delivers only a notification sent by the
  #   key owner", "subscribe drops notifications with malformed keys or wrong
  #   sharedWith").
  #   noNamespace cannot widen a key: it drops the namespace entirely, even a
  #   given one, and never changes sharedWith or sharedBy ("notify with
  #   noNamespace true ignores a given namespace").
  # Impersonation: outbound notify refuses mismatched sharedBy, public, or
  #   cached keys upfront before any lookup, and inbound notifications compare
  #   canonical sender and owner ("notify with mismatched sharedBy rejects with
  #   bad_key and sends nothing", "notify with public or cached flag rejects
  #   with bad_key and sends nothing", "matches the sender and the key owner by
  #   canonical atSign").

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

  Scenario: notify with mismatched sharedBy rejects with bad_key and sends nothing
    Given an open session as @alice
    When notify is called with sharedBy @carol
    Then it rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify with public or cached flag rejects with bad_key and sends nothing
    Given an open session
    When notify is called with public true or cached true
    Then each rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify with empty or invalid key or invalid sharedWith rejects with bad_key and sends nothing
    Given an open session
    When notify is called with an empty or malformed key or an invalid sharedWith
    Then each rejects with bad_key
    And nothing is sent to the atServer

  Scenario: notify with noNamespace true sends the key with no namespace
    Given an open session in namespace wavi, as @alice
    When notify is called on key k shared with @bob with noNamespace true
    Then the notified key is @bob:k@alice
    And the session namespace is not applied

  Scenario: notify without noNamespace applies the session namespace
    Given an open session in namespace wavi, as @alice
    When notify is called on key k shared with @bob without noNamespace
    Then the notified key is @bob:k.wavi@alice

  Scenario: notify with noNamespace true ignores a given namespace
    Given an open session in namespace wavi, as @alice
    When notify is called on key k shared with @bob with namespace other and noNamespace true
    Then the notified key is @bob:k@alice

  Scenario: notify with noNamespace true still rejects a key name that carries more key text and sends nothing
    Given an open session as @alice
    When notify is called with noNamespace true on a key name holding an @, a colon or a doubled dot
    Then each rejects with bad_key
    And nothing is sent to the atServer

  Scenario: bridge notify passes noNamespace as given and refuses a non-boolean
    Given an open bridge session
    When notify is called with noNamespace true, then with noNamespace as a string
    Then the session receives the first key with noNamespace true
    And the second rejects with bad_key and the session receives nothing for it

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

  Scenario: close stops delivering subscription events and errors even if the stream emits before cancel settles
    Given an active subscription whose stream emits an event or error after close starts
    When close is called
    Then neither onEvent nor onError receives post-close deliveries

  Scenario: a subscription whose stream completes is removed
    Given an active subscription
    When its notification stream completes
    Then the session no longer holds that subscription

  Scenario: subscribe cancels immediately if close occurs during startListening
    Given an open session whose startListening triggers close synchronously
    When subscribe is called
    Then the subscription is cancelled immediately without leaking into active subscriptions

  Scenario: bridge subscribe drops notifications and errors after session is closed
    Given a BridgeSession subscription and a session marked closed
    When the underlying session emits a notification or error
    Then neither the JS event callback nor the JS error callback is invoked
