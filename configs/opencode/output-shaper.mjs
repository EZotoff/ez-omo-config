// configs/opencode/output-shaper.mjs
// Output Shaper config-layer plugin surface (scaffold — hooks are no-ops)

import { loadConfig } from "./output-shaper/config.mjs";
import { logInfo, logWarn, setLogLevel } from "./output-shaper/logging.mjs";

export default async function outputShaperPlugin(ctx) {
  const config = await loadConfig();
  if (!config) {
    logWarn("No outputShaper config loaded; plugin running in no-op mode");
    return noopHooks();
  }

  setLogLevel(config.logLevel);

  if (config.enabled === false) {
    logWarn("outputShaper disabled in config; plugin running in no-op mode");
    return noopHooks();
  }

  logInfo("Plugin loaded (scaffold)");

  return {
    chat: {
      // T2: merge clamp options into output.options for target models
      params: async () => {},
    },
    // T3: push static terseness instruction into output.system
    "experimental.chat.system.transform": async () => {},
  };
}

function noopHooks() {
  return {
    chat: {
      params: async () => {},
    },
    "experimental.chat.system.transform": async () => {},
  };
}
