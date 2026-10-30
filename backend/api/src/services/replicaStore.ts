import type { ScreenshotStore } from "./screenshots";
import { MAX_REPLICA_BYTES } from "./replicas";

/** Keys per R2 delete: one bad key may fail the whole call, so batches stay as small as Storage's (REMOVE_BATCH). */
const DELETE_BATCH = 100;

/**
 * Private R2 bucket `shoo-replicas` through the Worker binding (D-alief-C23): page replicas and new
 * favicons (`-icon.`, D-alief-C27). No public URL, no r2.dev, no CORS; objects are only served by
 * GET /replicas/{id} and GET /favicons/{id}. R2 has no bucket-level size or type guard, so put
 * refuses anything over the replica limit itself (SECURITY T6).
 */
export class R2ReplicaStore implements ScreenshotStore {
  constructor(private readonly bucket: R2Bucket) {}

  async put(path: string, bytes: Uint8Array, contentType: string): Promise<void> {
    if (bytes.length > MAX_REPLICA_BYTES) throw new Error("r2 put: object too large");
    await this.bucket.put(path, bytes, { httpMetadata: { contentType } });
  }

  async get(path: string): Promise<Response | undefined> {
    const object = await this.bucket.get(path);
    return object ? new Response(object.body) : undefined;
  }

  async remove(paths: string[]): Promise<void> {
    for (let i = 0; i < paths.length; i += DELETE_BATCH) await this.bucket.delete(paths.slice(i, i + DELETE_BATCH));
  }
}
