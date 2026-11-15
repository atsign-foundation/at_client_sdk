/** The reasons an `AtClient` call can fail; apps branch on these, never on message text. */
export type AtErrorCode =
  /** This browser holds no passkey for the atSign; enroll it with `AtClient.enroll`. */
  | 'no_passkey_here'
  /** The passkey ceremony returned no credential, or the passkey's record did not authenticate. */
  | 'passkey_lost'
  /** The browser or authenticator cannot evaluate passkey PRF. */
  | 'prf_unavailable'
  /** The atServer refused this enrollment's PKAM login. */
  | 'pkam_refused'
  /** The restored public keys differ from the ones the atServer holds. */
  | 'public_key_mismatch'
  /** Another tab holds the atSign's first-setup lock and did not release it in time. */
  | 'setup_lock_timeout'
  /** The client did not come online. */
  | 'offline'
  /** Onboarding or enrollment started but did not finish. */
  | 'onboarding_incomplete'
  /** The enrollment request was denied, or the pairing call was refused by the atServer. */
  | 'enrollment_denied'
  /** The client is closed. */
  | 'closed'
  /** This page, option or session cannot do what was asked. */
  | 'unsupported'
  /** Any failure with no code of its own. */
  | 'internal'
  /** A key is malformed, or `namespace` is missing. */
  | 'bad_key'
  /** A subscription buffered more than 4096 events the app did not consume. */
  | 'overflow';

const codes: ReadonlySet<string> = new Set<AtErrorCode>([
  'no_passkey_here',
  'passkey_lost',
  'prf_unavailable',
  'pkam_refused',
  'public_key_mismatch',
  'setup_lock_timeout',
  'offline',
  'onboarding_incomplete',
  'enrollment_denied',
  'closed',
  'unsupported',
  'internal',
  'bad_key',
  'overflow',
]);

/** The error every `AtClient` call rejects with; branch on `code`. */
export class AtError extends Error {
  /** Which failure this is; see `AtErrorCode`. */
  code: AtErrorCode;

  constructor(message: string, code: AtErrorCode) {
    super(message);
    this.name = 'AtError';
    this.code = code;
  }
}

/**
 * The `AtError` for whatever a bridge call rejected or threw: a `{code,
 * message}` object keeps its code when it is a known one; anything else is
 * `internal`.
 */
export function toAtError(reason: unknown): AtError {
  if (reason instanceof AtError) return reason;
  if (typeof reason === 'object' && reason !== null) {
    const { code, message } = reason as { code?: unknown; message?: unknown };
    const text = typeof message === 'string' ? message : String(reason);
    if (typeof code === 'string' && codes.has(code)) return new AtError(text, code as AtErrorCode);
    return new AtError(text, 'internal');
  }
  return new AtError(String(reason), 'internal');
}
