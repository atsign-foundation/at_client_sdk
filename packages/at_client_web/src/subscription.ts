/**
 * An unbounded buffer read as an async iterator. `end()` and `return()` finish
 * it: waiting readers settle done, the buffer is dropped, later pushes are
 * ignored and `onDone` runs once.
 */
export class EventQueue<T> implements AsyncIterableIterator<T> {
  private readonly buffer: T[] = [];
  private waiters: Array<(result: IteratorResult<T>) => void> = [];
  private done = false;

  constructor(private readonly onDone: () => void) {}

  push(value: T): void {
    if (this.done) return;
    const waiter = this.waiters.shift();
    if (waiter) waiter({ value, done: false });
    else this.buffer.push(value);
  }

  end(): void {
    if (this.done) return;
    this.done = true;
    this.buffer.length = 0;
    const waiters = this.waiters;
    this.waiters = [];
    for (const waiter of waiters) waiter({ value: undefined, done: true });
    this.onDone();
  }

  next(): Promise<IteratorResult<T>> {
    if (this.buffer.length > 0) {
      return Promise.resolve({ value: this.buffer.shift() as T, done: false });
    }
    if (this.done) return Promise.resolve({ value: undefined, done: true });
    return new Promise((resolve) => this.waiters.push(resolve));
  }

  return(): Promise<IteratorResult<T>> {
    this.end();
    return Promise.resolve({ value: undefined, done: true });
  }

  [Symbol.asyncIterator](): this {
    return this;
  }
}
