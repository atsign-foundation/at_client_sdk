Feature: A stopped client refuses every later call that does work

  After stop(), a call that would do work for the atSign fails with
  StoppedException, as put, putText, putBinary, putMeta, get, getMeta,
  delete, keyExists, getAtKeys, getKeys, notifyStatus, notifyList, setSPP,
  getOTP and enrollments.otp already do. Calls that report state rather than
  do work answer as before: ensureReachable reports failed with
  StoppedException as its cause, connection reads (offline, stopped),
  dataEvents is closed, and the plain accessors (isStopped, atSign,
  getPreferences) still answer. AtClient's notify, notifyChange, notifyAll,
  startMonitor and compaction jobs are gone in 4.0, so they are not among
  them: notifications go through notificationService.

  Races: a call racing stop() already fails with StoppedException once the
  stop lands; this adds no ordering.
  Replay, DoS: none arise; nothing is sent.
  Forgery and impersonation: none arise; a stopped client does nothing more
  for its atSign.

  Scenario: collection() on a stopped client throws StoppedException
    Given a client that has been stopped
    When collection() is called on it
    Then it throws StoppedException

  Scenario: A stopped client's services throw StoppedException
    Given a client that has been stopped
    When its syncService, notificationService or enrollmentService is read
    Then each read throws StoppedException, and so do send, subscribe, sync, isInSync and enrollments.pending through them
