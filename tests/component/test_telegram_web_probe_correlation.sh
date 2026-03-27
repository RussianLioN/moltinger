#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../lib/test_helpers.sh"

NODE_SCRIPT="$PROJECT_ROOT/scripts/telegram-web-user-probe.mjs"

run_component_telegram_web_probe_correlation_tests() {
    start_timer

    test_start "component_telegram_web_probe_selects_exact_outgoing_probe_message"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { findOutgoingProbeMessage } = await import(process.env.NODE_SCRIPT);
const probe = findOutgoingProbeMessage([
  { mid: 10, direction: "out", text: "/status" },
  { mid: 15, direction: "out", text: " /status  " },
  { mid: 16, direction: "out", text: "/status extra" },
  { mid: 18, direction: "in", text: "ready" }
], "/status", 12);
if (!probe || probe.mid !== 15 || probe.text !== "/status") {
  throw new Error(`unexpected probe match: ${JSON.stringify(probe)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Probe correlation should pick the newest exact outgoing match after baseline"
    fi

    test_start "component_telegram_web_probe_strips_telegram_time_suffix_from_outgoing_message"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { findOutgoingProbeMessage } = await import(process.env.NODE_SCRIPT);
const probe = findOutgoingProbeMessage([
  { mid: 51, direction: "out", text: "/status22:1022:10" },
  { mid: 52, direction: "in", text: "ok" }
], "/status", 0);
if (!probe || probe.mid !== 51 || probe.text !== "/status") {
  throw new Error(`expected normalized outgoing probe, got ${JSON.stringify(probe)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Outgoing probe correlation must ignore Telegram Web time/status suffixes appended to bubble text"
    fi

    test_start "component_telegram_web_probe_ignores_stale_incoming_messages"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { findAttributedReply } = await import(process.env.NODE_SCRIPT);
const reply = findAttributedReply([
  { mid: 21, direction: "in", text: "old reply" },
  { mid: 22, direction: "out", text: "/status" },
  { mid: 22, direction: "service", text: "delivered" }
], 22);
if (reply !== null) {
  throw new Error(`expected no attributed reply, got ${JSON.stringify(reply)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Stale bot replies before the current sent message must not be matched"
    fi

    test_start "component_telegram_web_probe_matches_first_incoming_after_sent_mid"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { findAttributedReply } = await import(process.env.NODE_SCRIPT);
const reply = findAttributedReply([
  { mid: 31, direction: "out", text: "/status" },
  { mid: 32, direction: "in", text: "first reply" },
  { mid: 33, direction: "in", text: "second reply" }
], 31);
if (!reply || reply.mid !== 32 || reply.text !== "first reply") {
  throw new Error(`unexpected attributed reply: ${JSON.stringify(reply)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Attributed reply should be the first incoming message after the sent probe"
    fi

    test_start "component_telegram_web_probe_waits_for_stable_final_reply_before_passing"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { waitForReplySettleWithCollector } = await import(process.env.NODE_SCRIPT);
const snapshots = [
  [{ mid: 31, direction: "out", text: "/status" }],
  [
    { mid: 31, direction: "out", text: "/status" },
    { mid: 32, direction: "in", text: "Проверяю снова" }
  ],
  [
    { mid: 31, direction: "out", text: "/status" },
    { mid: 32, direction: "in", text: "Проверяю снова, включая поиск в системе" }
  ],
  [
    { mid: 31, direction: "out", text: "/status" },
    { mid: 32, direction: "in", text: "Проверяю снова, включая поиск в системе" },
    { mid: 33, direction: "in", text: "Timed out: Agent run timed out after 30s" }
  ],
  [
    { mid: 31, direction: "out", text: "/status" },
    { mid: 32, direction: "in", text: "Проверяю снова, включая поиск в системе" },
    { mid: 33, direction: "in", text: "Timed out: Agent run timed out after 30s" }
  ],
  [
    { mid: 31, direction: "out", text: "/status" },
    { mid: 32, direction: "in", text: "Проверяю снова, включая поиск в системе" },
    { mid: 33, direction: "in", text: "Timed out: Agent run timed out after 30s" }
  ]
];
let index = 0;
const result = await waitForReplySettleWithCollector({
  collectMessagesFn: async () => snapshots[Math.min(index++, snapshots.length - 1)],
  sleepFn: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  settleMs: 150,
  maxWaitMs: 1200,
  sentMid: 31,
});
if (!result.ok || !result.settled || !result.replyMessage || result.replyMessage.mid !== 33) {
  throw new Error(`unexpected settled result: ${JSON.stringify(result)}`);
}
if (!/Timed out/i.test(result.replyMessage.text)) {
  throw new Error(`expected final timeout reply, got ${JSON.stringify(result.replyMessage)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Probe must settle on the final stable incoming reply instead of passing on an early intermediate response"
    fi

    test_start "component_telegram_web_probe_waits_for_quiet_window_before_send"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { waitForQuietWindowWithCollector } = await import(process.env.NODE_SCRIPT);
const snapshots = [
  [{ mid: 10, direction: "in", text: "late previous reply" }],
  [{ mid: 10, direction: "in", text: "late previous reply" }],
  [{ mid: 10, direction: "in", text: "late previous reply" }]
];
let index = 0;
const result = await waitForQuietWindowWithCollector({
  collectMessagesFn: async () => snapshots[Math.min(index++, snapshots.length - 1)],
  sleepFn: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  quietMs: 150,
  maxWaitMs: 900,
  baselineMaxMid: 0,
});
if (!result.ok || result.baselineMaxMid !== 10) {
  throw new Error(`unexpected quiet-window success result: ${JSON.stringify(result)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Quiet window should wait for late pre-send activity to settle before probe attribution starts"
    fi

    test_start "component_telegram_web_probe_fails_when_chat_never_quiets"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { waitForQuietWindowWithCollector } = await import(process.env.NODE_SCRIPT);
let mid = 40;
const result = await waitForQuietWindowWithCollector({
  collectMessagesFn: async () => [{ mid: mid++, direction: "in", text: `noise-${mid}` }],
  sleepFn: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  quietMs: 150,
  maxWaitMs: 500,
  baselineMaxMid: 0,
});
if (result.ok || !Array.isArray(result.recentMessages) || result.recentMessages.length === 0) {
  throw new Error(`expected quiet-window failure, got ${JSON.stringify(result)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Probe must fail instead of passing on a noisy chat with unbounded unrelated activity"
    fi

    test_start "component_telegram_web_probe_classifies_required_failure_codes"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { classifyFailure } = await import(process.env.NODE_SCRIPT);
const requiredCodes = [
  "missing_session_state",
  "ui_drift",
  "chat_open_failure",
  "stale_chat_noise",
  "send_failure",
  "bot_no_response",
  "progress_preface_without_final",
];
for (const code of requiredCodes) {
  const failure = classifyFailure(code, "send");
  if (failure.code !== code || failure.stage !== "send" || typeof failure.summary !== "string" || failure.summary.length === 0) {
    throw new Error(`bad failure mapping for ${code}: ${JSON.stringify(failure)}`);
  }
}
NODE
    then
        test_pass
    else
        test_fail "Probe must export a stable failure taxonomy for all required authoritative Telegram Web failure classes"
    fi

    test_start "component_telegram_web_probe_marks_model_not_found_as_error_signature"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { isReplyErrorSignature } = await import(process.env.NODE_SCRIPT);
const badReply = "model 'openai-codex::gpt-5.4' not found. available: [\"zai::glm-5\"]";
const goodReply = "Статус: Online | Модель: zai::glm-5";
if (!isReplyErrorSignature(badReply)) {
  throw new Error("expected model-not-found reply to be treated as error signature");
}
if (isReplyErrorSignature(goodReply)) {
  throw new Error("expected healthy status reply to remain clean");
}
NODE
    then
        test_pass
    else
        test_fail "Model-not-found responses must be rejected by reply-quality checks"
    fi

    test_start "component_telegram_web_probe_marks_activity_log_replies_as_error_signature"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { isReplyErrorSignature } = await import(process.env.NODE_SCRIPT);
const badReply = "Activity log • nodes_list • sessions_list • cron • missing 'action' parameter";
const goodReply = "Я на месте. - Имя: Молтингер - Пользователь: Сергей - Модель: openai-codex::gpt-5.4";
if (!isReplyErrorSignature(badReply)) {
  throw new Error("expected activity-log/tool-error reply to be treated as error signature");
}
if (isReplyErrorSignature(goodReply)) {
  throw new Error("expected healthy presence/status reply to remain clean");
}
NODE
    then
        test_pass
    else
        test_fail "Activity-log timeout summaries must be rejected by reply-quality checks"
    fi

    test_start "component_telegram_web_probe_rejects_emoji_prefixed_internal_telemetry_replies"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { isReplyErrorSignature } = await import(process.env.NODE_SCRIPT);
const badReplies = [
  "📋 Activity log • 💻 Running: `find /home/moltis/.moltis/skills -maxdepth 2 -type...` • 🧠 Searching memory...",
  "💻 Running: `find /home/moltis/.moltis/skills -maxdepth 2 -print`",
  "🧠 Searching memory..."
];
for (const badReply of badReplies) {
  if (!isReplyErrorSignature(badReply)) {
    throw new Error(`expected telemetry reply to be rejected: ${badReply}`);
  }
}
NODE
    then
        test_pass
    else
        test_fail "Emoji-prefixed activity/tool-progress replies must be rejected by reply-quality checks"
    fi

    test_start "component_telegram_web_probe_detects_recent_invalid_pre_send_incoming_activity"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { findInvalidIncomingActivityMessages } = await import(process.env.NODE_SCRIPT);
const invalid = findInvalidIncomingActivityMessages([
  { mid: 77, direction: "out", text: "/status" },
  { mid: 78, direction: "in", text: "📋 Activity log • 💻 Running: `find ...`" },
  { mid: 79, direction: "in", text: "🧠 Searching memory..." },
  { mid: 80, direction: "in", text: "Нормальный человеческий ответ" }
]);
if (!Array.isArray(invalid) || invalid.length !== 2) {
  throw new Error(`expected two invalid incoming activity messages, got ${JSON.stringify(invalid)}`);
}
if (invalid[0].mid !== 78 || invalid[1].mid !== 79) {
  throw new Error(`unexpected invalid incoming mids: ${JSON.stringify(invalid)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Probe must classify recent incoming activity/tool-progress leakage before send attribution begins"
    fi

    test_start "component_telegram_web_probe_detects_human_progress_preface_replies"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { isLikelyProgressPreface } = await import(process.env.NODE_SCRIPT);
const prefaced = [
  "Сначала открою канал и быстро посмотрю.",
  "Проверю источник и вернусь с ответом.",
  "Let me open the page first.",
  "Checking the channel now."
];
const finalAnswers = [
  "Канал про новости и комментарии об ИИ и автоматизации.",
  "docs.moltis.org",
  "Timed out: Agent run timed out after 30s"
];
for (const reply of prefaced) {
  if (!isLikelyProgressPreface(reply)) {
    throw new Error(`expected progress preface to be detected: ${reply}`);
  }
}
for (const reply of finalAnswers) {
  if (isLikelyProgressPreface(reply)) {
    throw new Error(`expected final/error reply to remain non-preface: ${reply}`);
  }
}
NODE
    then
        test_pass
    else
        test_fail "Probe must recognize short human-facing progress prefaces so it does not pass too early"
    fi

    test_start "component_telegram_web_probe_waits_past_progress_preface_for_final_reply"
    if NODE_SCRIPT="$NODE_SCRIPT" node --input-type=module <<'NODE'
import process from "node:process";
const { extendReplySettlePastProgressPreface } = await import(process.env.NODE_SCRIPT);
const initialResult = {
  ok: true,
  settled: true,
  settleWaitMs: 5000,
  replyObservedAtMs: 1000,
  replyMessage: { mid: 218926, direction: "in", text: "Сначала открою канал и быстро посмотрю." },
  latestIncoming: { mid: 218926, direction: "in", text: "Сначала открою канал и быстро посмотрю." }
};
let called = false;
const refined = await extendReplySettlePastProgressPreface({
  initialResult,
  deadlineMs: 60_000,
  nowMs: () => 10_000,
  waitForReplySettleFn: async (afterMid, remainingMs) => {
    called = true;
    if (afterMid !== 218926 || remainingMs <= 0) {
      throw new Error(`unexpected follow-up wait args: afterMid=${afterMid}, remainingMs=${remainingMs}`);
    }
    return {
      ok: true,
      settled: true,
      settleWaitMs: 18000,
      replyObservedAtMs: 28000,
      replyMessage: { mid: 218930, direction: "in", text: "Timed out: Agent run timed out after 30s" },
      latestIncoming: { mid: 218930, direction: "in", text: "Timed out: Agent run timed out after 30s" }
    };
  }
});
if (!called) {
  throw new Error("expected follow-up settle wait after progress preface");
}
if (!refined.replyMessage || refined.replyMessage.mid !== 218930) {
  throw new Error(`expected final follow-up reply, got ${JSON.stringify(refined)}`);
}
if (!refined.prefaceReplyMessage || refined.prefaceReplyMessage.mid !== 218926) {
  throw new Error(`expected original preface reply to be preserved, got ${JSON.stringify(refined)}`);
}
NODE
    then
        test_pass
    else
        test_fail "Probe must keep waiting after a progress preface and settle on the later final reply"
    fi

    generate_report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_component_telegram_web_probe_correlation_tests
fi
