/**
 * Resolve a CSS color string to a value the Canvas 2D API accepts.
 *
 * The canvas `strokeStyle`/`fillStyle` setters silently ignore CSS custom
 * properties (`var(--x)`) — assigning one leaves the previous value in place, so
 * traces drawn with `ctx.strokeStyle = 'var(--ecg)'` render in the wrong colour.
 * This resolves `var(--token[, fallback])` to the concrete colour computed on
 * :root (falling back to the literal, then to the given default) so callers can
 * keep passing theme tokens.
 */
const cache = new Map<string, string>();

export function resolveCssColor(color: string, fallback = '#000000'): string {
  if (typeof color !== 'string') return fallback;
  const trimmed = color.trim();
  if (!trimmed.startsWith('var(')) return trimmed; // already a literal colour
  const cached = cache.get(trimmed);
  if (cached != null) return cached;

  // Parse `var(--name)` or `var(--name, fallback)`.
  const inner = trimmed.slice(4, trimmed.lastIndexOf(')'));
  const commaIdx = inner.indexOf(',');
  const name = (commaIdx >= 0 ? inner.slice(0, commaIdx) : inner).trim();
  const declFallback = commaIdx >= 0 ? inner.slice(commaIdx + 1).trim() : '';

  let resolved = declFallback || fallback;
  if (typeof window !== 'undefined' && typeof getComputedStyle === 'function') {
    const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    if (value) resolved = value;
  }
  cache.set(trimmed, resolved);
  return resolved;
}
