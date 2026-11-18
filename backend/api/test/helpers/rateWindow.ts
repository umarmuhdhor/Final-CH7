/**
 * Miniflare's Rate Limiting binding counts in fixed windows on the wall clock
 * (`epoch = Math.floor(Date.now() / (period * 1000))`, ratelimit-object.worker.js). A burst that
 * crosses a window edge starts counting again and never reaches the limit, so a "the N+1st request
 * is 429" test fails now and then (CI, 8 Nov). Call before such a burst: when less than `needMs` is
 * left in the current window, wait for the next one. Give the test a timeout above `needMs`.
 */
export async function atWindowStart(periodSeconds: number, needMs = 3000): Promise<void> {
  const period = periodSeconds * 1000;
  const left = period - (Date.now() % period);
  if (left < needMs) await new Promise((resolve) => setTimeout(resolve, left + 50));
}
