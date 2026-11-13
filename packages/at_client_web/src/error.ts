/** The reasons an `AtClient` call can fail; apps branch on these, never on message text. */
export type AtErrorCode =
  | 'no_passkey_here'
  | 'passkey_lost'
  | 'prf_unavailable'
  | 'pkam_refused'
  | 'public_key_mismatch'
  | 'setup_lock_timeout'
  | 'offline'
  | 'onboarding_incomplete'
  | 'enrollment_denied'
  | 'closed'
  | 'unsupported'
  | 'internal'
  | 'bad_key';

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
]);

export class AtError extends Error {
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
