Feature: EnrollmentRequestList's feedback overlay is removed once, and goes with the list

  After an approval or a denial, EnrollmentRequestList shows a feedback
  overlay. It is removed when the user taps it or its close button, or after
  3 seconds, whichever comes first, and when the list itself is removed.

  Races: a tap and the 3-second timer, or two taps before the next frame,
  remove the overlay once.
  Replay: none arises; the overlay sends nothing.
  DoS: the list keeps only the overlays still showing, so many approvals and
  denials leave no timers behind.
  Forgery and impersonation: none arise; the overlay's names are escaped as
  approver_sees_names_escaped.feature says, and this changes only when it is
  removed.

  Scenario: Tapping the feedback overlay removes it, and its timer then does nothing
    Given EnrollmentRequestList showing the feedback overlay after an approval
    When the user taps the overlay, and 3 seconds then pass
    Then the overlay is gone and no error is reported

  Scenario: The feedback overlay is removed after 3 seconds
    Given EnrollmentRequestList showing the feedback overlay after a denial
    When 3 seconds pass
    Then the overlay is gone

  @race
  Scenario: Two taps before the next frame remove the feedback overlay once
    Given EnrollmentRequestList showing the feedback overlay
    When the user taps it twice before the next frame
    Then the overlay is gone and no error is reported

  Scenario: The feedback overlay goes when the request list goes
    Given EnrollmentRequestList showing the feedback overlay
    When the list is removed from the screen before 3 seconds pass
    Then the overlay is gone too, and no error is reported
