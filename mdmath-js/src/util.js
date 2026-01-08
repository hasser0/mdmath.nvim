import { createHash } from "node:crypto";

const sha256 = createHash("sha256");

export function sha256Hash(data) {
    sha256.update(data, "utf8");
    return sha256.copy().digest("hex");
}
