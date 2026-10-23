import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

/** True when this module is the script node was started with. Compares real paths, so a symlinked start still counts:
 *  a check that silently does nothing because of a symlink would look like a pass. */
export function isMain(metaUrl) {
    try {
        return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(metaUrl));
    } catch {
        return false;
    }
}
