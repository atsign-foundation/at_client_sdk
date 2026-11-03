Feature: at_activate approve warns about a request at the legacy key exchange on a post-quantum atSign

  A device enrolled at the legacy key exchange carries no key package, so
  its approval conveys no namespace key. On an atSign that publishes a
  namespace key, the device's floor is pqReady, so at its first start it
  re-enrolls itself and asks the atSign's other enrollments for its
  namespace keys. approve says so when it approves such a request, and
  approves it as asked: the request's key exchange is the requester's to
  set, and the warning decides nothing.

  Races: the atSign can publish its first namespace key between the
  warning and the device's first start; the device's own start applies the
  floor either way.
  Replay: none arise; nothing new is sent or signed.
  DoS: none arise; approve reads the atSign's own namespace-key records
  once per run.
  Forgery and impersonation: none arise; what is approved, and by whom, is
  unchanged.

  Scenario: Approving a request at the legacy key exchange on an atSign that publishes a namespace key warns
    Given @alice publishes a namespace key, and a device's enrollment request at the legacy key exchange
    When the atSign's manager runs at_activate approve for it
    Then approve warns that the device will re-enroll itself at its first start and ask for its namespace keys, and that denying it and requesting again at pqReady avoids both, and approves the request as asked
