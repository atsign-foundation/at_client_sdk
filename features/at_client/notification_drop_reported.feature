Feature: A notification a client cannot deliver is reported

  A notification the client gives up on, such as one sealed post-quantum to
  a client whose posture reads no post-quantum data, is logged at warning
  with its key and the reason, and emitted on
  NotificationService.droppedEvents. For a client whose posture reads no
  post-quantum data the reason names the posture, says the notification is
  lost, and says to configure pqReady or above for later ones. A CLIBase
  program shows warnings on stderr by default.

  Races: none new; a drop is reported once, from the loop that drops it.
  Replay: none arise; nothing is sent.
  DoS: one log line and one event per notification dropped, which the
  sender already bounds.
  Forgery and impersonation: none arise; what is delivered, and to whom,
  is unchanged.

  Scenario: A notification a client cannot decrypt is reported, not lost silently
    Given a CLIBase program at PqPosture.legacy subscribed to a namespace a peer seals to
    When a notification sealed to the namespace key arrives
    Then the program's stderr carries a warning naming the notification and the posture, and droppedEvents emits it
