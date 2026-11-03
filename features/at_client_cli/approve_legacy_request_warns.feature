Feature: at_activate approve warns about a request at the legacy key exchange on a post-quantum atSign

  A device enrolled at the legacy key exchange carries no key package, so
  its approval conveys no namespace key. On an atSign that publishes a
  namespace key, the device reads none of the atSign's post-quantum data
  unless its app runs at pqReady or above, when it re-enrolls itself at its
  first start and asks the atSign's other enrollments for its namespace
  keys. approve says so when it approves such a request, and approves it as
  asked: the request's key exchange is the requester's to set, and the
  warning decides nothing.

  Races: the atSign can publish its first namespace key between the
  warning and the device's first start; then the device's own posture
  decides, as above.
  Replay: none arise; nothing new is sent or signed.
  DoS: none arise; approve reads the atSign's own namespace-key records
  once per run.
  Forgery and impersonation: none arise; what is approved, and by whom, is
  unchanged.

  Scenario: Approving a request at the legacy key exchange on an atSign that publishes a namespace key warns
    Given @alice publishes a namespace key, and a device's enrollment request at the legacy key exchange
    When the atSign's manager runs at_activate approve for it
    Then approve warns that the approval conveys none of the atSign's namespace keys, so the device reads none of its post-quantum data unless its app runs at pqReady or above (then it re-enrolls at its first start and asks for them), and that revoking it and requesting again at pqReady conveys them at approval; and it approves the request as asked
