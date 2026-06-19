/** Minimal typed event emitter. `on` returns an unsubscribe function. */
type AnyFn = (...args: any[]) => void;

export class Emitter<Events extends Record<keyof Events, AnyFn>> {
  private listeners: Partial<{ [K in keyof Events]: Set<Events[K]> }> = {};

  on<K extends keyof Events>(event: K, cb: Events[K]): () => void {
    const set = (this.listeners[event] ??= new Set<Events[K]>());
    set.add(cb);
    return () => {
      this.listeners[event]?.delete(cb);
    };
  }

  emit<K extends keyof Events>(event: K, ...args: Parameters<Events[K]>): void {
    const set = this.listeners[event];
    if (!set) return;
    for (const cb of set) (cb as AnyFn)(...args);
  }

  clear(): void {
    this.listeners = {};
  }
}
