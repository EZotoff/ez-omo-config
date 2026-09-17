import { createSignalTracker } from "../../configs/opencode/skill-nudger/signals.mjs";
import { bench } from "./lib.mjs";

const config = {
  windowSize: 15,
  repeatFailureThreshold: 2,
  loopThreshold: 8,
};
const tracker = createSignalTracker(config);
const result = bench(
  "skill-nudger.observe-failed-tool",
  (iteration) => tracker.observe({
    sessionID: `bench-${iteration}`,
    tool: "bash",
    args: { command: "npm test" },
    outputText: "Error: command failed with exit code 1",
  }),
  { iterations: 10_000 },
);

process.stdout.write(`${JSON.stringify(result)}\n`);
