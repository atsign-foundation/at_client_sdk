import { afterEach, describe, expect, it, vi } from 'vitest';
import { loadBridge, setBridgeLoader, type Bridge } from '../src/loader.js';

const fakeBridge = {} as Bridge;

afterEach(() => {
  setBridgeLoader();
  vi.unstubAllGlobals();
});

describe('loadBridge with an injected loader', () => {
  it('does not load until asked', () => {
    const loader = vi.fn(async () => fakeBridge);
    setBridgeLoader(loader);
    expect(loader).not.toHaveBeenCalled();
  });

  it('loads once however many calls and callers', async () => {
    const loader = vi.fn(async () => fakeBridge);
    setBridgeLoader(loader);
    const [a, b] = await Promise.all([loadBridge(), loadBridge()]);
    const c = await loadBridge();
    expect(loader).toHaveBeenCalledTimes(1);
    expect([a, b, c]).toEqual([fakeBridge, fakeBridge, fakeBridge]);
  });

  it('retries after a failed load', async () => {
    const loader = vi
      .fn<() => Promise<Bridge>>()
      .mockRejectedValueOnce(new Error('network'))
      .mockResolvedValue(fakeBridge);
    setBridgeLoader(loader);
    await expect(loadBridge()).rejects.toThrow('network');
    expect(await loadBridge()).toBe(fakeBridge);
    expect(loader).toHaveBeenCalledTimes(2);
  });
});

describe('the default loader', () => {
  function stubDocument() {
    const scripts: Array<{ src: string; onload?: () => void; onerror?: () => void }> = [];
    vi.stubGlobal('document', {
      createElement: () => {
        const script: (typeof scripts)[number] = { src: '' };
        scripts.push(script);
        return script;
      },
      head: { appendChild: () => {} },
    });
    return scripts;
  }

  it('injects dart/at_client.js once and resolves with the global it installs', async () => {
    const scripts = stubDocument();
    const [a, b] = [loadBridge(), loadBridge()];
    expect(scripts).toHaveLength(1);
    expect(scripts[0]!.src).toMatch(/\/dart\/at_client\.js$/);
    vi.stubGlobal('__atsignAtClientWeb', fakeBridge);
    scripts[0]!.onload!();
    expect(await a).toBe(fakeBridge);
    expect(await b).toBe(fakeBridge);
    expect(await loadBridge()).toBe(fakeBridge);
    expect(scripts).toHaveLength(1);
  });

  it('reuses a bridge that is already installed without injecting', async () => {
    const scripts = stubDocument();
    vi.stubGlobal('__atsignAtClientWeb', fakeBridge);
    expect(await loadBridge()).toBe(fakeBridge);
    expect(scripts).toHaveLength(0);
  });

  it('rejects with an internal AtError when the script fails to load', async () => {
    const scripts = stubDocument();
    const loading = loadBridge();
    scripts[0]!.onerror!();
    await expect(loading).rejects.toMatchObject({ name: 'AtError', code: 'internal' });
  });

  it('rejects with an internal AtError when the script installs nothing', async () => {
    vi.useFakeTimers();
    try {
      const scripts = stubDocument();
      const loading = loadBridge();
      const settled = expect(loading).rejects.toMatchObject({ code: 'internal' });
      scripts[0]!.onload!();
      await vi.advanceTimersByTimeAsync(10_000);
      await settled;
    } finally {
      vi.useRealTimers();
    }
  });
});
