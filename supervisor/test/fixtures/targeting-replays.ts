export const targetingReplays = [
  {
    seq: 26388, timestamp: "2026-10-09T15:27:25.043Z", sessionID: "ses_f1108700affeFomUkAFXunUixU",
    root: "/home/ezotoff/ez-omo-bench", ledgerType: "TICK_SKIPPED",
    reply: "Say A/B/C.", synthetic: true, action: "ACCEPT", operatorInputRequested: true,
  },
  {
    seq: 26391, timestamp: "2026-10-09T15:30:11.318Z", sessionID: "ses_f4c3c89a0ffeBP3idV4r2giQHY",
    root: "/home/ezotoff/ez-omo-bench", ledgerType: "TICK_SKIPPED",
    reply: "Which way?", synthetic: false, action: "ABSTAIN", operatorInputRequested: true,
  },
  {
    seq: 25128, timestamp: "2026-10-06T21:40:21.617Z", sessionID: "ses_eedf74c55ffeLktXhpK7EwOdRz",
    root: "/home/ezotoff/ez-omo-bench", ledgerType: "TICK_DECIDED",
    reply: "A1 validation is running on uni-pc with a watcher armed. Runtime est. 15–60 min; watcher will wake me with the verdict, then I proceed to P2.",
    synthetic: false, action: "ABSTAIN", operatorInputRequested: false,
    wakeHandle: { kind: "systemd-unit", ref: "fixture-dead-watcher.service" },
  },
] as const
