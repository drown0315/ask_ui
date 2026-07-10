import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";

import { copyDistToBridge } from "./copy-dist-to-bridge.mjs";

test("copyDistToBridge replaces bridge web contents with Vite dist", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "ask-ui-copy-web-"));
  const webDistDir = path.join(root, "dist");
  const bridgeWebDir = path.join(root, "bridge-web");

  try {
    await mkdir(path.join(webDistDir, "assets"), { recursive: true });
    await mkdir(bridgeWebDir, { recursive: true });
    await writeFile(path.join(webDistDir, "index.html"), "<div>Ask UI</div>");
    await writeFile(path.join(webDistDir, "assets", "app.js"), "app");
    await writeFile(path.join(bridgeWebDir, "old.txt"), "old");

    await copyDistToBridge({
      webDistDir,
      bridgeWebDir,
    });

    assert.equal(
      await readFile(path.join(bridgeWebDir, "index.html"), "utf8"),
      "<div>Ask UI</div>",
    );
    assert.equal(
      await readFile(path.join(bridgeWebDir, "assets", "app.js"), "utf8"),
      "app",
    );
    await assert.rejects(readFile(path.join(bridgeWebDir, "old.txt"), "utf8"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
