import { describe, expect, it, vi } from 'vitest';
import { AtError } from '../src/error.js';
import { EventQueue, MAX_BUFFERED_EVENTS } from '../src/subscription.js';

describe('EventQueue', () => {
  it('buffers pushes made before anyone iterates', async () => {
    const queue = new EventQueue<number>(() => {});
    queue.push(1);
    queue.push(2);
    expect(await queue.next()).toEqual({ value: 1, done: false });
    expect(await queue.next()).toEqual({ value: 2, done: false });
  });

  it('hands a push to a waiting next()', async () => {
    const queue = new EventQueue<string>(() => {});
    const pending = queue.next();
    queue.push('a');
    expect(await pending).toEqual({ value: 'a', done: false });
  });

  it('buffers up to the cap', async () => {
    expect(MAX_BUFFERED_EVENTS).toBe(4096);
    const onDone = vi.fn();
    const queue = new EventQueue<number>(onDone);
    for (let i = 0; i < MAX_BUFFERED_EVENTS; i++) queue.push(i);
    expect(onDone).not.toHaveBeenCalled();
    let last = -1;
    for (let i = 0; i < MAX_BUFFERED_EVENTS; i++) last = (await queue.next()).value as number;
    expect(last).toBe(MAX_BUFFERED_EVENTS - 1);
  });

  it('overflows on the push past the cap: ends once, drops the buffer, next() rejects once', async () => {
    const onDone = vi.fn();
    const queue = new EventQueue<number>(onDone);
    for (let i = 0; i <= MAX_BUFFERED_EVENTS; i++) queue.push(i);
    expect(onDone).toHaveBeenCalledTimes(1);
    queue.push(1);
    const error = await queue.next().then(
      () => undefined,
      (e: unknown) => e,
    );
    expect(error).toBeInstanceOf(AtError);
    expect((error as AtError).code).toBe('overflow');
    expect(await queue.next()).toEqual({ value: undefined, done: true });
    await queue.return();
    expect(onDone).toHaveBeenCalledTimes(1);
  });

  it('return() ends the queue once, runs onDone once and settles waiters', async () => {
    const onDone = vi.fn();
    const queue = new EventQueue<number>(onDone);
    const waiting = queue.next();
    expect(await queue.return()).toEqual({ value: undefined, done: true });
    expect(await waiting).toEqual({ value: undefined, done: true });
    await queue.return();
    expect(onDone).toHaveBeenCalledTimes(1);
    expect(await queue.next()).toEqual({ value: undefined, done: true });
  });

  it('drops pushes after it has ended and discards what was buffered', async () => {
    const queue = new EventQueue<number>(() => {});
    queue.push(1);
    queue.end();
    queue.push(2);
    expect(await queue.next()).toEqual({ value: undefined, done: true });
  });

  it('is its own async iterator and ends a for-await on break', async () => {
    const onDone = vi.fn();
    const queue = new EventQueue<number>(onDone);
    queue.push(1);
    queue.push(2);
    for await (const value of queue) {
      expect(value).toBe(1);
      break;
    }
    expect(onDone).toHaveBeenCalledTimes(1);
  });
});
