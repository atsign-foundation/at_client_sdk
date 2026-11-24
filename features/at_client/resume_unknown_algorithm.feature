Feature: Resuming an enrollment whose signing algorithm this build does not know is refused by name

  Atsign.resumeEnrollment returns an AtKeys store's one pending request as a
  PendingEnrollment, which signs with the request's signing algorithm. A
  request filed by a build that knows an algorithm this one does not cannot
  continue here, so resumeEnrollment refuses it by name rather than failing
  with an error that names nothing.

  Races: none; the resume decides from one read of the store. Replay: none;
  the refusal comes before any connection is opened, and nothing is sent.
  DoS: the message quotes the algorithm's name clipped, as it quotes ids.
  Forgery and impersonation: only the app's own builds write the store, and
  they already hold the request's keys.

  Scenario: Resuming a pending enrollment whose signing algorithm this build does not know names it
    Given an AtKeys store holding @alice's one pending enrollment request, whose signing algorithm this build does not know
    When the app calls resumeEnrollment for @alice
    Then it throws AtKeysUnusableException with cause noAuthenticationKeypair, naming the enrollment id and the algorithm, and saying to resume it with a build that can sign with that algorithm, before it opens a connection
