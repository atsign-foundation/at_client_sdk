import { AtError } from '@atsign/at_client_web';

/** The element with [id], which the page's markup must hold. */
export function byId<T extends HTMLElement = HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (element === null) throw new Error(`missing #${id}`);
  return element as T;
}

/** `code: message` for an `AtError`, so a page shows what apps branch on. */
export function describeError(error: unknown): string {
  if (error instanceof AtError) return `${error.code}: ${error.message}`;
  return `internal: ${error instanceof Error ? error.message : String(error)}`;
}

/** Appends a line of [text] to [log] and scrolls to it. */
export function appendLine(log: HTMLElement, text: string, className = ''): HTMLElement {
  const line = document.createElement('div');
  line.className = className;
  line.textContent = text;
  log.append(line);
  log.scrollTop = log.scrollHeight;
  return line;
}
