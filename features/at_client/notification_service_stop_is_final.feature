Feature: Stopping a notification service is final

  stopAllSubscriptions() stops a notification service for good: every
  subscription ends, the listener stops, and subscribe(),
  subscribeFiltered() and startListening() throw StoppedException from then
  on. Its stopNotificationsListener parameter is deprecated and ignored, so
  the listener stops whatever a caller passes. To pause the listener and
  keep the subscriptions, an app calls stopListening() and later
  startListening(). To receive notifications after a stop, it builds a new
  client. A client's stop() stops its notification service the same way.

  Races: two stops at once are one stop, since the first sets the stopped
  flag before anything awaits and the second returns. A subscribe racing a
  stop either throws StoppedException or gets a stream that closes. Only
  code in the app's own process can call either, and it already holds the
  client.
  Replay: a stop sends nothing and stores nothing, and a stopped listener
  takes in nothing, so it marks nothing as received.
  Denial of service: only the app can stop its own service; nothing a sender
  does causes a stop. Ignoring false removes the one state in which a
  connected listener took in notifications that no subscriber received.
  Forgery and impersonation: none arise. A stop reads no input from the
  wire and asserts no identity.

  Scenario: Stopping a notification service stops its listener even when told to keep it
    # packages/at_client/test/notification_service_stop_test.dart
    Given a notification service whose listener is listening
    When the app calls stopAllSubscriptions with stopNotificationsListener false
    Then the listener stops: targetListenerState and currentListenerState are notConnected

  Scenario: A notification service the app stopped refuses a subscription while its client runs
    # packages/at_client/test/notification_service_stop_test.dart
    Given a running client whose notification service the app has stopped with stopAllSubscriptions
    When the app calls subscribe on that service
    Then it throws StoppedException

  Scenario: A notification service stopped with stopNotificationsListener false refuses to start listening
    # packages/at_client/test/notification_service_stop_test.dart
    Given a running client whose notification service the app has stopped with stopNotificationsListener false
    When the app calls startListening on that service
    Then it throws StoppedException
