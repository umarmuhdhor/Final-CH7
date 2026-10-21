import type { Env } from "../env";

/**
 * Removes screenshot objects from the private `screenshots` bucket.
 * TODO(sync:alief): Storage API delete — replace in fase 09 (BE-scans), when uploads exist.
 * Until then no scan has a screenshot object, so there is nothing to delete.
 */
export async function deleteScreenshots(_env: Env, paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  console.log(JSON.stringify({ event: "screenshots_delete_pending", count: paths.length }));
}
