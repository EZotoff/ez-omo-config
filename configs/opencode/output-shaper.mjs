// configs/opencode/output-shaper.mjs
// Output Shaper config-layer plugin surface — terseness injection + reasoning-effort dialing

import { loadConfig } from "./output-shaper/config.mjs";
import { logInfo, logTiming, logWarn, nowMs, setLogLevel } from "./output-shaper/logging.mjs";
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

  logInfo("Plugin loaded");

  return {
    "chat.params": async (input, output) => {
      const providerID = input.model?.providerID;
      const modelID = input.model?.id;
      // Skip excluded providers (anthropic, github-copilot), providers not in
      // CLAMP_TABLE, and models outside a provider's allowlist
      if (!isTargetModel(providerID, modelID)) return;
      const sessionID = input.sessionID;
      if (!sessionID) return;
      // Only dial thinking on resume-after-tool-result turns; new-question
      // turns and non-resume turns leave output.options untouched
      const resumeStartedAt = nowMs();
      const isResume = await isResumeAfterToolResult(ctx, sessionID);
      logTiming("chat.params.resume", resumeStartedAt); // emits hook=chat.params.resume
      if (!isResume) return;
      const clampStartedAt = nowMs();
      const clamp = getClampOptions(providerID, config.resumeThinkingLevel);
      if (!clamp) {
        logTiming("chat.params.clamp", clampStartedAt); // emits hook=chat.params.clamp
        return;
      }
      output.options[clamp.field] = clamp.value;
      logTiming("chat.params.clamp", clampStartedAt);
      const valueStr = typeof clamp.value === "string" ? clamp.value : JSON.stringify(clamp.value);
      logInfo(`Clamped ${providerID}/${modelID} resume turn: ${clamp.field}=${valueStr}`);
    },
    // Push static terseness instruction into output.system (all providers)
    "experimental.chat.system.transform": async (input, output) => {
      const startedAt = nowMs();
      if (Array.isArray(output.system)) {
        output.system.push(config.tersenessInstruction);
        logInfo(`Terseness injected: ${input.model?.providerID ?? "?"}/${input.model?.id ?? "?"}`);
      }
      logTiming("system.transform", startedAt);
    },
  };
}

function noopHooks() {
  return {
    "chat.params": async () => {},
    "experimental.chat.system.transform": async () => {},
  };
}
