import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const launcherDir = dirname(fileURLToPath(import.meta.url));
const nodeDir = dirname(process.execPath);
const pathsFile =
  process.env.PI_DELEGATE_PATHS ||
  join(launcherDir, "pi-delegate-paths.json");

function packageRoots(root) {
  return {
    sdkRoot: join(root, "@earendil-works", "pi-coding-agent"),
    delegateRoot: join(root, "pi-delegate-mcp"),
  };
}

function hasPackages(roots) {
  return (
    existsSync(join(roots.sdkRoot, "package.json")) &&
    existsSync(join(roots.delegateRoot, "package.json"))
  );
}

function loadConfiguredRoots() {
  if (!existsSync(pathsFile)) return null;

  const config = JSON.parse(readFileSync(pathsFile, "utf8"));
  if (!config.sdkRoot || !config.delegateRoot) {
    throw new Error(
      `Invalid pi package path file at ${pathsFile}: sdkRoot and delegateRoot are required.`,
    );
  }

  const roots = {
    sdkRoot: config.sdkRoot,
    delegateRoot: config.delegateRoot,
  };
  if (!hasPackages(roots)) {
    throw new Error(
      `The package paths in ${pathsFile} are stale. Re-run scripts/install.ps1.`,
    );
  }
  return roots;
}

function discoverRoots() {
  const candidates = [
    join(nodeDir, "node_modules"),
    process.env.PI_NODE_MODULES_ROOT,
    process.env.APPDATA
      ? join(process.env.APPDATA, "npm", "node_modules")
      : null,
    process.env.LOCALAPPDATA
      ? join(
          process.env.LOCALAPPDATA,
          "CodexPi",
          "npm-global",
          "node_modules",
        )
      : null,
  ].filter(Boolean);

  for (const root of candidates) {
    const roots = packageRoots(root);
    if (hasPackages(roots)) return roots;
  }

  throw new Error(
    "Could not find @earendil-works/pi-coding-agent and pi-delegate-mcp. " +
      "Run scripts/install.ps1 to create pi-delegate-paths.json.",
  );
}

const { sdkRoot, delegateRoot } = loadConfiguredRoots() ?? discoverRoots();

const { SettingsManager } = await import(
  pathToFileURL(
    join(sdkRoot, "dist", "core", "settings-manager.js"),
  ).href
);
const { applyHttpProxySettings, configureHttpDispatcher } = await import(
  pathToFileURL(join(sdkRoot, "dist", "core", "http-dispatcher.js")).href
);

const agentDir =
  process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
const settings = SettingsManager.create(process.cwd(), agentDir, {
  projectTrusted: false,
});

applyHttpProxySettings(settings.getGlobalSettings().httpProxy);
configureHttpDispatcher(settings.getHttpIdleTimeoutMs());

await import(pathToFileURL(join(delegateRoot, "dist", "index.js")).href);
