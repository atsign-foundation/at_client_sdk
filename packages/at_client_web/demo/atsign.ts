/** [atSign] trimmed, lower-cased and with a leading `@`, for comparing two atSigns. */
export function canonicalAtSign(atSign: string): string {
  const name = atSign.trim().toLowerCase();
  return name.startsWith('@') ? name : `@${name}`;
}
