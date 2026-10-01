// tests/promise-catcher/harness.mjs
// Test harness for promise-catcher plugin

import { mkdtempSync, writeFileSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PLUGIN_PATH = join(import.meta.dirname, "..", "..", "configs", "opencode", "promise-catcher.mjs");

function assert(cond, msg) {
  if (!cond) throw new Error(`ASSERT FAILED: ${msg}`);
}

function assertEq(actual, expected, msg) {
  if (actual !== expected) {
    throw new Error(`ASSERT FAILED: ${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

// Fresh temp config+log per setup; writes the plugin's globalThis test hook.
async function setup(config = {}) {
  const dir = mkdtempSync(join(tmpdir(), "pc-test-"));
  const cfgPath = join(dir, "config.json");
  const logPath = join(dir, "plugin.log");
  writeFileSync(cfgPath, JSON.stringify({ enabled: true, dry_run: false, max_wakes_per_session: 2, ...config }));
  globalThis.__promiseCatcherTestPaths = { config: cfgPath, log: logPath };
  const mod = await import(`${PLUGIN_PATH}?t=${Date.now()}-${Math.random().toString(36).slice(2)}`);
  return { mod, logPath, writeConfig: (c) => writeFileSync(cfgPath, JSON.stringify(c)) };
}

const readLog = (p) => { try { return readFileSync(p, "utf8"); } catch { return ""; } };

function msg(role, text, extra = {}) {
  return {
    info: { id: extra.id ?? `m_${Math.random().toString(36).slice(2, 8)}`, role, time: { created: 1, completed: extra.completed ?? (role === "assistant" ? 2 : undefined) }, ...extra.info },
    parts: [{ type: "text", text }],
  };
}

function bgSpawnMsg(id = "msg_spawn") {
  return {
    info: { id, role: "assistant", time: { created: 1, completed: 2 } },
    parts: [{ type: "tool", tool: "task", state: { input: { run_in_background: true, prompt: "watch the job" }, status: "completed", output: "Background task launched: bg_1a2b3c4d" } }],
  };
}

function mockCtx(sessions, msgs) {
  const injections = [];
  return {
    ctx: {
      directory: "/w/project",
      client: {
        session: {
          list: async () => ({ data: sessions }),
          messages: async () => ({ data: msgs }),
          promptAsync: async (r) => { injections.push(r); },
        },
        tui: { showToast: async () => {} },
      },
    },
    injections,
  };
}

const session = (id, over = {}) => ({ info: { id, directory: "/w/project", parentID: null, ...over } });

async function idle(plugin, sid) {
  await plugin.event({ event: { type: "session.status", properties: { sessionID: sid, status: { type: "idle" } } } });
}

// --- Cases ---

async function casePromiseDetected() {
  const { mod } = await setup();
  const sid = "ses_pc1";
  const msgs = [msg("user", "monitor the run"), msg("assistant", "Job launched. I'll monitor with backoff until it completes.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 1, `one wake expected, got ${injections.length}`);
  assert(injections[0].path.id === sid, "wake targets the idle session");
  const text = injections[0].body.parts[0].text;
  assert(text.includes("AUTOMATED WAKE (promise-catcher)"), "wake prompt branded");
  assert(text.includes("run_in_background watcher subagent"), "wake prompt offers the watcher option");
}

async function caseNoPromise() {
  const { mod } = await setup();
  const sid = "ses_pc2";
  const msgs = [msg("user", "run tests"), msg("assistant", "All 12 tests pass. Report: 12/12 green.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake for a normal closing message");
}

async function caseArmedText() {
  const { mod } = await setup();
  const sid = "ses_pc3";
  const msgs = [msg("user", "check with oracle"), msg("assistant", "Consulting Oracle in the background. I'll monitor — waiting on the Oracle notification.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake when text signals an armed wait");
}

async function casePendingBgTask() {
  const { mod } = await setup();
  const sid = "ses_pc4";
  // bg task spawned earlier, never completed -> skip
  const msgs = [bgSpawnMsg(), msg("user", "status?"), msg("assistant", "Watcher running. I'll keep monitoring.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake while a background task is pending");
}

async function caseCompletedBgTask() {
  const { mod } = await setup();
  const sid = "ses_pc5";
  // bg task spawned AND its completion reminder arrived later -> no longer armed
  const msgs = [
    bgSpawnMsg(),
    msg("user", "<system-reminder>\n[BACKGROUND TASK COMPLETED]\n- `bg_1a2b3c4d`: oracle task\n</system-reminder>"),
    msg("assistant", "Oracle done. I'll keep monitoring the run."),
  ];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 1, "wake fires when the bg task already completed");
}

async function caseUserLast() {
  const { mod } = await setup();
  const sid = "ses_pc6";
  const msgs = [msg("assistant", "I'll monitor."), msg("user", "ok")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake when the last message is from the user");
}

async function caseIncomplete() {
  const { mod } = await setup();
  const sid = "ses_pc7";
  const msgs = [msg("user", "go"), { info: { id: "m_inc", role: "assistant", time: { created: 1 } }, parts: [{ type: "text", text: "I'll monitor." }] }];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake for an incomplete assistant message");
}

async function caseRunningTool() {
  const { mod } = await setup();
  const sid = "ses_pc8";
  const msgs = [
    msg("user", "go"),
    { info: { id: "m_rt", role: "assistant", time: { created: 1, completed: 2 } }, parts: [
      { type: "text", text: "I'll monitor." },
      { type: "tool", tool: "question", state: { input: {}, status: "running" } },
    ] },
  ];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "no wake while a tool part is still running (waits-for-human)");
}

async function caseDryRun() {
  const { mod, logPath } = await setup({ dry_run: true });
  const sid = "ses_pc9";
  const msgs = [msg("user", "go"), msg("assistant", "I'll probe again shortly.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "dry-run injects nothing");
  const log = readLog(logPath);
  assert(log.includes("WOULD wake"), "dry-run logs the would-wake verdict");
}

async function caseWakeCapAndDeadLetter() {
  const { mod, logPath } = await setup({ max_wakes_per_session: 2 });
  const sid = "ses_pc10";
  const mk = (id) => [msg("user", "go"), msg("assistant", "I'll keep monitoring.", { id })];
  let msgs = mk("m1");
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid); // wake 1
  assert(injections.length === 1, "first wake dispatched");
  // agent woke, promised again, went idle
  ctx.client.session.messages = async () => ({ data: [msg("user", "AUTOMATED WAKE..."), msg("assistant", "Still waiting. I'll monitor.", { id: "m2" })] });
  await idle(plugin, sid); // wake 2
  assert(injections.length === 2, "second wake dispatched");
  ctx.client.session.messages = async () => ({ data: [msg("user", "AUTOMATED WAKE..."), msg("assistant", "Again: I'll monitor.", { id: "m3" })] });
  await idle(plugin, sid); // cap reached
  assert(injections.length === 2, "no third wake past the cap");
  const log = readLog(logPath);
  assert(log.includes("dead-letter"), "dead-letter logged at cap");
}

async function caseNoRewakeSameMessage() {
  const { mod } = await setup();
  const sid = "ses_pc11";
  const msgs = [msg("user", "go"), msg("assistant", "I'll monitor.", { id: "same" })];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  await idle(plugin, sid); // duplicate idle event for the same message
  assert(injections.length === 1, "same assistant message never woken twice");
}

async function caseChildSessionSkipped() {
  const { mod } = await setup();
  const sid = "ses_pc12";
  const msgs = [msg("user", "go"), msg("assistant", "I'll monitor.")];
  const { ctx, injections } = mockCtx([session(sid, { parentID: "ses_parent" })], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "child (subagent) sessions are skipped");
}

async function caseExemptions() {
  const { mod } = await setup({ exempt_directories: ["/w/project"] });
  const sid = "ses_pc13";
  const msgs = [msg("user", "go"), msg("assistant", "I'll monitor.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "exempt directory skipped");

  const { mod: mod2 } = await setup({ exempt_sessions: ["ses_pc14"] });
  const msgs2 = [msg("user", "go"), msg("assistant", "I'll monitor.")];
  const { ctx: ctx2, injections: inj2 } = mockCtx([session("ses_pc14")], msgs2);
  const plugin2 = await mod2.default(ctx2);
  await idle(plugin2, "ses_pc14");
  assert(inj2.length === 0, "exempt session skipped");
}

async function caseDisabled() {
  const { mod } = await setup({ enabled: false });
  const sid = "ses_pc15";
  const msgs = [msg("user", "go"), msg("assistant", "I'll monitor.")];
  const { ctx, injections } = mockCtx([session(sid)], msgs);
  const plugin = await mod.default(ctx);
  await idle(plugin, sid);
  assert(injections.length === 0, "disabled plugin does nothing");
}

async function caseEvaluatePure() {
  const { mod } = await setup();
  const { evaluatePromise } = mod;
  assertEq(evaluatePromise([]).reason, "no-messages", "empty input");
  assertEq(evaluatePromise([msg("assistant", "plain text")]).reason, "no-promise", "plain text");
  assertEq(evaluatePromise([msg("assistant", "I'll track both metrics")]).ok, true, "track promise detected");
  assertEq(evaluatePromise([msg("assistant", "Next probe in 2 min")]).ok, true, "next-probe detected");
  assertEq(evaluatePromise([msg("assistant", "I'll check back in ~60s")]).ok, true, "check-back detected");
  assertEq(evaluatePromise([msg("assistant", "The watcher subagent bg_9f8e7d6 will report; meanwhile I'll keep monitoring")]).reason, "armed-text", "bg id in text = armed");
}

// --- Runner ---

const cases = {
  "promise-detected": casePromiseDetected,
  "no-promise": caseNoPromise,
  "armed-text": caseArmedText,
  "pending-bg-task": casePendingBgTask,
  "completed-bg-task": caseCompletedBgTask,
  "user-last": caseUserLast,
  "incomplete": caseIncomplete,
  "running-tool": caseRunningTool,
  "dry-run": caseDryRun,
  "wake-cap-dead-letter": caseWakeCapAndDeadLetter,
  "no-rewake-same-message": caseNoRewakeSameMessage,
  "child-session-skipped": caseChildSessionSkipped,
  "exemptions": caseExemptions,
  "disabled": caseDisabled,
  "evaluate-pure": caseEvaluatePure,
};

const arg = process.argv[process.argv.indexOf("--case") + 1];
if (process.argv.includes("--case") && arg && cases[arg]) {
  await cases[arg]();
  console.log(`PASS: ${arg}`);
  process.exit(0);
}
let failed = 0;
for (const [name, fn] of Object.entries(cases)) {
  try {
    await fn();
    console.log(`PASS: ${name}`);
  } catch (e) {
    failed++;
    console.error(`FAIL: ${name}: ${e.message}`);
  }
}
console.log(`promise-catcher harness: pass ${Object.keys(cases).length - failed} | fail ${failed}`);
process.exit(failed ? 1 : 0);
