import { cp, mkdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const webRoot = path.resolve(path.dirname(scriptPath), "..");
const repoRoot = path.resolve(webRoot, "..", "..");

export async function copyDistToBridge({
  webDistDir = path.join(webRoot, "dist"),
  bridgeWebDir = path.join(repoRoot, "apps", "bridge", "web"),
} = {}) {
  await assertFileExists(path.join(webDistDir, "index.html"));
  await rm(bridgeWebDir, { recursive: true, force: true });
  await mkdir(bridgeWebDir, { recursive: true });
  await cp(webDistDir, bridgeWebDir, { recursive: true });
}

async function assertFileExists(filePath) {
  const fileStat = await stat(filePath).catch(() => null);
  if (!fileStat?.isFile()) {
    throw new Error(
      `Expected built Web index.html at ${filePath}. Run npm run build first.`,
    );
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  await copyDistToBridge();
}
