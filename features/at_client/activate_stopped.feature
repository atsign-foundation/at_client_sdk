Feature: An activation over a stopped lookup says it was stopped and leaves no client running
  Atsign.activate may be given the atLookUp to activate over. Once the
  activation has completed, it opens the client with a first connect that
  authenticates by PKAM. A caller that supplied the atLookUp and stops it
  while that first connect runs gets the StoppedException a stopped atLookUp
  raises, rather than an offline client over a connection that is stopped.
  The client the activation opened is stopped, so none is left running for
  the Atsign.

  Scenario: Atsign.activate over a supplied atLookUp that its caller stops while the activation's client first connects throws StoppedException and leaves no client running
    # packages/at_client/test/lifecycle/activate_test.dart
    #   test 'Atsign.activate over a supplied connection stopped while its client first connects throws StoppedException and leaves no client live'
    Given an activation of @alice over an atLookUp its caller supplied
    When the caller stops the atLookUp while the activation's client first connects
    Then Atsign.activate throws StoppedException
    And no client for @alice is running

  Scenario: Atsign.activate over a supplied atLookUp whose client first connect fails with an ordinary connection error returns the offline client
    # packages/at_client/test/lifecycle/activate_test.dart
    #   test 'Atsign.activate over a supplied connection whose client first connect fails with an ordinary connection error returns the offline client'
    Given an activation of @alice over an atLookUp its caller supplied
    When the activation's client first connects and the connection fails with an error that is not a stop
    Then Atsign.activate returns the client
    And the client for @alice is running, offline

  Scenario: Atsign.activate of a post-quantum atSign over an atLookUp that its caller stops while the signing root is minted throws StoppedException and leaves no client running
    # packages/at_client/test/lifecycle/activate_test.dart
    #   test 'Atsign.activate over a supplied connection stopped while its post-quantum signing root is minted throws StoppedException and leaves no client live'
    Given a post-quantum activation of @alice over an atLookUp its caller supplied
    When the caller stops the atLookUp while the activation mints the signing root
    Then Atsign.activate throws StoppedException
    And no client for @alice is running
