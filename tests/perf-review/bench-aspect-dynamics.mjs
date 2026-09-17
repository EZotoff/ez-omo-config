import { readFileSync } from "node:fs";

import { prefilterContext } from "../../configs/opencode/aspect-dynamics/context.mjs";
import { scoreAspects } from "../../configs/opencode/aspect-dynamics/heuristics.mjs";
import { bench } from "./lib.mjs";

const emotionsV1 = JSON.parse(
  readFileSync(new URL("../../configs/opencode/aspect-dynamics/sets/emotions-v1.json", import.meta.url), "utf8"),
);
const context = {
  messages: Array.from({ length: 20 }, (_, index) => ({
    id: `message-${index + 1}`,
    role: index % 2 === 0 ? "user" : "assistant",
    text: index === 18
      ? "This is frustrating and urgent; I need this fixed right now."
      : `Synthetic turn ${Math.floor(index / 2) + 1}, message ${index + 1}.`,
  })),
  latestAssistantMessageId: "message-20",
};
const activeSets = [emotionsV1];
const config = { heuristicPreFilter: true };

const results = [
  bench("aspect-dynamics-prefilterContext", () => prefilterContext(context, activeSets, config)),
  bench("aspect-dynamics-scoreAspects", () => scoreAspects(context, activeSets)),
];

console.log(JSON.stringify(results));
