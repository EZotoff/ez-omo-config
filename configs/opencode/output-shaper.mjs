// configs/opencode/output-shaper.mjs
// Output Shaper config-layer plugin surface (scaffold — hooks are no-ops)

import { loadConfig } from "./output-shaper/config.mjs";
import { logInfo, logWarn, setLogLevel } from "./output-shaper/logging.mjs";
import { getClampOptions, isTargetModel } from "./output-shaper/model-gating.mjs";
import { isResumeAfterToolResult } from "./output-shaper/resume-detector.mjs";

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
    "chat.params": async (input, output) => {
      const providerID = input.model?.providerID;
      const modelID = input.model?.id;
      // Skip excluded providers (anthropic, github-copilot) and any provider
      // not in CLAMP_TABLE (unknown providers)
      if (!isTargetModel(providerID)) return;
      const sessionID = input.sessionID;
      if (!sessionID) return;
      // Only dial thinking on resume-after-tool-result turns; new-question
      // turns and non-resume turns leave output.options untouched
      const isResume = await isResumeAfterToolResult(ctx, sessionID);
      if (!isResume) return;
      const clamp = getClampOptions(providerID, config.resumeThinkingLevel);
      if (!clamp) return;
      output.options[clamp.field] = clamp.value;
      logInfo(`Clamped ${providerID}/${modelID} resume turn: ${clamp.field}=${clamp.value}`);
    },
    // T3: push static terseness instruction into output.system
    "experimental.chat.system.transform": async (input, output) => {
      if (Array.isArray(output.system)) {
        output.system.push(config.tersenessInstruction);
      }
    },
  };
}

function noopHooks() {
  return {
    "chat.params": async () => {},
    "experimental.chat.system.transform": async () => {},
  };
}
