const PLAINTEXT = 'at_client_wasm prf spike: the sealed .atKeys stand-in';
const HKDF_INFO = new TextEncoder().encode('at_client_wasm/kek/v1');
const DB = 'at_client_wasm_prf_spike';
const STORE = 'blobs';

const logEl = document.getElementById('log');
const row = {
  ua: navigator.userAgent,
  secureContext: window.isSecureContext,
  capabilities: null,
  createPrfEnabled: null,
  createPrfFirstLen: null,
  largeBlobSupported: null,
  getPrfFirstLen: null,
  sealed: false,
  unlockedAfterReload: null,
  error: null,
};

function log(msg, cls = '') {
  const line = document.createElement('div');
  line.className = cls;
  line.textContent = msg;
  logEl.append(line);
}

const rand = (n) => crypto.getRandomValues(new Uint8Array(n));
const b64 = (u8) => btoa(String.fromCharCode(...new Uint8Array(u8)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

function state() {
  return JSON.parse(localStorage.getItem('prf-spike') ?? 'null');
}
function saveState(s) {
  localStorage.setItem('prf-spike', JSON.stringify(s));
}

function idb(mode, fn) {
  return new Promise((resolve, reject) => {
    const open = indexedDB.open(DB, 1);
    open.onupgradeneeded = () => open.result.createObjectStore(STORE);
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const tx = open.result.transaction(STORE, mode);
      const req = fn(tx.objectStore(STORE));
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    };
  });
}

async function prfOutput() {
  const s = state();
  if (!s) throw new Error('not registered');
  const cred = await navigator.credentials.get({
    publicKey: {
      challenge: rand(32),
      allowCredentials: [{ type: 'public-key', id: unb64(s.credentialId) }],
      userVerification: 'required',
      extensions: { prf: { eval: { first: unb64(s.prfSalt) } } },
    },
  });
  const first = cred.getClientExtensionResults().prf?.results?.first;
  row.getPrfFirstLen = first ? first.byteLength : 0;
  log(`get: prf.results.first = ${row.getPrfFirstLen} bytes`, first ? 'ok' : 'bad');
  if (!first) throw new Error('authenticator returned no PRF output');
  return new Uint8Array(first);
}

async function kek(prf, hkdfSalt) {
  const ikm = await crypto.subtle.importKey('raw', prf, 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: hkdfSalt, info: HKDF_INFO },
    ikm,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

async function register() {
  const prfSalt = rand(32);
  const cred = await navigator.credentials.create({
    publicKey: {
      rp: { name: 'at_client_wasm prf spike', id: location.hostname },
      user: { id: rand(16), name: 'prf-spike', displayName: 'prf-spike' },
      challenge: rand(32),
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },
        { type: 'public-key', alg: -257 },
      ],
      authenticatorSelection: { residentKey: 'required', userVerification: 'required' },
      extensions: { prf: { eval: { first: prfSalt } }, largeBlob: { support: 'preferred' } },
    },
  });
  const ext = cred.getClientExtensionResults();
  row.createPrfEnabled = ext.prf?.enabled ?? null;
  row.createPrfFirstLen = ext.prf?.results?.first?.byteLength ?? 0;
  row.largeBlobSupported = ext.largeBlob?.supported ?? null;
  saveState({ credentialId: b64(cred.rawId), prfSalt: b64(prfSalt), row });
  log(`create: prf.enabled=${row.createPrfEnabled}, results.first=${row.createPrfFirstLen} bytes, largeBlob.supported=${row.largeBlobSupported}`,
    row.createPrfEnabled ? 'ok' : 'bad');
}

async function seal() {
  const hkdfSalt = rand(32);
  const iv = rand(12);
  const key = await kek(await prfOutput(), hkdfSalt);
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(PLAINTEXT));
  await idb('readwrite', (s) => s.put({ hkdfSalt: b64(hkdfSalt), iv: b64(iv), ct: b64(ct) }, 'blob'));
  row.sealed = true;
  saveState({ ...state(), row });
  log(`seal: ${ct.byteLength} bytes into IndexedDB "${DB}" — now reload, then Unlock`, 'ok');
}

async function unlock() {
  const blob = await idb('readonly', (s) => s.get('blob'));
  if (!blob) throw new Error('no sealed blob in IndexedDB');
  const key = await kek(await prfOutput(), unb64(blob.hkdfSalt));
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(blob.iv) }, key, unb64(blob.ct));
  row.unlockedAfterReload = new TextDecoder().decode(pt) === PLAINTEXT;
  saveState({ ...state(), row });
  log(`unlock: plaintext ${row.unlockedAfterReload ? 'matches' : 'MISMATCH'}`, row.unlockedAfterReload ? 'ok' : 'bad');
}

function guard(fn) {
  return async () => {
    try {
      await fn();
    } catch (e) {
      row.error = `${e.name}: ${e.message}`;
      saveState({ ...(state() ?? {}), row });
      log(row.error, 'bad');
    }
  };
}

async function copyRow() {
  const r = row;
  const line = `| ${r.ua} | ${r.secureContext} | ${r.capabilities?.['extension:prf'] ?? '—'} | ${r.createPrfEnabled} | ${r.createPrfFirstLen} | ${r.getPrfFirstLen} | ${r.largeBlobSupported} | ${r.unlockedAfterReload} | ${r.error ?? ''} |`;
  try {
    await navigator.clipboard.writeText(line);
    log('row copied', 'ok');
  } catch {
    log(line);
  }
}

async function reset() {
  localStorage.removeItem('prf-spike');
  await new Promise((r) => { const d = indexedDB.deleteDatabase(DB); d.onsuccess = d.onerror = r; });
  location.reload();
}

document.getElementById('register').onclick = guard(register);
document.getElementById('seal').onclick = guard(seal);
document.getElementById('unlock').onclick = guard(unlock);
document.getElementById('copy').onclick = copyRow;
document.getElementById('reset').onclick = reset;

(async () => {
  Object.assign(row, state()?.row ?? {}, { ua: navigator.userAgent, secureContext: window.isSecureContext });
  row.capabilities = await window.PublicKeyCredential?.getClientCapabilities?.().catch(() => null) ?? null;
  log(`UA: ${row.ua}`, 'muted');
  log(`isSecureContext=${row.secureContext}; getClientCapabilities extension:prf=${row.capabilities?.['extension:prf'] ?? 'n/a'}`);
  if (state()) log(`registered; sealed=${row.sealed}`, 'muted');
})();
