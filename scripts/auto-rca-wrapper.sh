#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/auto-rca-wrapper.sh [options] -- <command> [args...]
  scripts/auto-rca-wrapper.sh --show-state
  scripts/auto-rca-wrapper.sh --reset-state

Options:
  --always-full         Force full RCA (L2) on every failure
  --full-threshold <N>  Promote to L2 on repeated signature (default: 3)
  --no-lessons-index    Skip lessons index update for L2
  --dry-run             Print RCA actions without writing files
  --show-state          Show wrapper signature counters
  --reset-state         Reset wrapper signature counters/log

Description:
  Economy-first auto-RCA wrapper for LLM command execution.
  - L1 (default): lightweight self-reflection + event log, low token cost
  - L2 (escalation): full RCA artifact in docs/rca/ + optional lessons index update
EOF
}

action="run"
always_full=false
full_threshold=3
no_lessons_index=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --always-full)
      always_full=true
      shift
      ;;
    --full-threshold)
      full_threshold="${2:-}"
      if [[ -z "${full_threshold}" || ! "${full_threshold}" =~ ^[0-9]+$ || "${full_threshold}" -lt 1 ]]; then
        echo "[auto-rca-wrapper] --full-threshold must be a positive integer" >&2
        exit 2
      fi
      shift 2
      ;;
    --no-lessons-index)
      no_lessons_index=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --show-state)
      action="show_state"
      shift
      ;;
    --reset-state)
      action="reset_state"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "[auto-rca-wrapper] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if git_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  in_git_repo=true
else
  in_git_repo=false
  git_root="$(pwd -P)"
fi

if [[ "${in_git_repo}" == true ]]; then
  state_dir="$(git rev-parse --git-path auto-rca)"
else
  state_dir="${git_root}/.tmp/auto-rca/state"
fi

events_dir="${git_root}/.tmp/auto-rca"
state_file="${state_dir}/signatures.tsv"
event_log="${events_dir}/events.log"

mkdir -p "${state_dir}" "${events_dir}"

show_state() {
  echo "state_file=${state_file}"
  echo "event_log=${event_log}"
  if [[ ! -f "${state_file}" ]]; then
    echo "signatures=0"
    return 0
  fi

  local total
  total="$(wc -l < "${state_file}" | tr -d '[:space:]')"
  echo "signatures=${total}"
  echo "top_signatures:"
  awk -F'\t' 'NF >= 2 { printf("  - %s repeat=%s cmd=%s\n", substr($1,1,8), $2, $4) }' "${state_file}" | sort -t= -k2,2nr | head -5
}

reset_state() {
  if [[ "${dry_run}" == true ]]; then
    echo "[auto-rca-wrapper] dry-run: would remove ${state_file} and ${event_log}" >&2
    return 0
  fi
  rm -f "${state_file}" "${event_log}"
  echo "[auto-rca-wrapper] state reset"
}

normalize_text() {
  sed 's/[[:space:]]\+/ /g' | sed 's/^ //; s/ $//'
}

detect_severity() {
  local code="$1"
  local msg="${2,,}"

  if [[ "${msg}" =~ permission\ denied|rm\ -rf|data\ loss|deleted|secret|credential\ leak ]]; then
    echo "P0"
    return
  fi
  if [[ "${msg}" =~ unauthorized|forbidden|branch\ drift|worktree\ drift|production ]]; then
    echo "P1"
    return
  fi
  if [[ "${msg}" =~ no\ such\ file|command\ not\ found|not\ found|missing\ script|missing ]]; then
    echo "P2"
    return
  fi
  if [[ "${code}" -ge 128 ]]; then
    echo "P1"
    return
  fi
  echo "P3"
}

detect_category() {
  local msg="${1,,}"
  if [[ "${msg}" =~ docker|container|image|network ]]; then
    echo "docker"
    return
  fi
  if [[ "${msg}" =~ ci|cd|workflow|github\ actions|pipeline ]]; then
    echo "cicd"
    return
  fi
  if [[ "${msg}" =~ delete|data\ loss|corrupt|backup ]]; then
    echo "data-loss"
    return
  fi
  echo "shell"
}

get_repeat_count() {
  local sig="$1"
  local previous="0"
  if [[ -f "${state_file}" ]]; then
    previous="$(awk -F'\t' -v s="${sig}" '$1==s {print $2; exit}' "${state_file}" 2>/dev/null || true)"
    previous="${previous:-0}"
  fi
  echo $((previous + 1))
}

persist_signature() {
  local sig="$1"
  local repeat_count="$2"
  local command_display="$3"
  local timestamp="$4"
  local tmp_file
  tmp_file="$(mktemp)"

  if [[ -f "${state_file}" ]]; then
    awk -F'\t' -v s="${sig}" '$1 != s {print $0}' "${state_file}" > "${tmp_file}"
  fi
  printf '%s\t%s\t%s\t%s\n' "${sig}" "${repeat_count}" "${timestamp}" "${command_display}" >> "${tmp_file}"
  mv "${tmp_file}" "${state_file}"
}

if [[ "${action}" == "show_state" ]]; then
  show_state
  exit 0
fi

if [[ "${action}" == "reset_state" ]]; then
  reset_state
  exit 0
fi

if [[ $# -eq 0 ]]; then
  echo "[auto-rca-wrapper] Missing command after --" >&2
  usage >&2
  exit 2
fi

command=("$@")
command_display="$(printf '%q ' "${command[@]}")"
command_display="${command_display% }"

tmp_stdout="$(mktemp)"
tmp_stderr="$(mktemp)"
cleanup() {
  rm -f "${tmp_stdout}" "${tmp_stderr}"
}
trap cleanup EXIT

set +e
"${command[@]}" > >(tee "${tmp_stdout}") 2> >(tee "${tmp_stderr}" >&2)
exit_code=$?
set -e

if [[ ${exit_code} -eq 0 ]]; then
  exit 0
fi

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
date_stamp="$(date +%F)"
primary_error="$(sed -n '1p' "${tmp_stderr}" | tr '\r' ' ' | normalize_text)"
if [[ -z "${primary_error}" ]]; then
  primary_error="command failed without stderr output"
fi

signature_input="${command_display}|${exit_code}|${primary_error}"
signature="$(printf '%s' "${signature_input}" | shasum -a 256 | awk '{print $1}')"
short_sig="${signature:0:8}"

repeat_count="$(get_repeat_count "${signature}")"
severity="$(detect_severity "${exit_code}" "${primary_error}")"
category="$(detect_category "${primary_error}")"

full_mode=false
if [[ "${always_full}" == true || "${repeat_count}" -ge "${full_threshold}" || "${severity}" == "P0" || "${severity}" == "P1" ]]; then
  full_mode=true
fi

if [[ "${dry_run}" == false ]]; then
  persist_signature "${signature}" "${repeat_count}" "${command_display}" "${timestamp}"
  printf '%s\tcode=%s\tsev=%s\trepeat=%s\tsig=%s\tcmd=%s\n' \
    "${timestamp}" "${exit_code}" "${severity}" "${repeat_count}" "${short_sig}" "${command_display}" >> "${event_log}"
fi

mode="L1"
if [[ "${full_mode}" == true ]]; then
  mode="L2"
fi

slug="$(basename "${command[0]}")"
slug="$(printf '%s' "${slug}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"
if [[ -z "${slug}" ]]; then
  slug="command"
fi

rca_report=""
lessons_status="skipped"
if [[ "${full_mode}" == true ]]; then
  rca_report="${git_root}/docs/rca/${date_stamp}-auto-rca-${slug}-${short_sig}.md"
  if [[ "${dry_run}" == false ]]; then
    mkdir -p "$(dirname "${rca_report}")"
    cat > "${rca_report}" <<EOF
---
title: "Auto-RCA: ${slug} failure (${short_sig})"
date: ${date_stamp}
severity: ${severity}
category: ${category}
tags: [auto-rca, llm, wrapper, ${slug}]
root_cause: "Execution assumptions were not validated before running command."
---

# RCA: Auto-triggered command failure

**Дата:** ${date_stamp}
**Статус:** In Progress
**Влияние:** Command failed with exit code ${exit_code}
**Контекст:** Auto-RCA wrapper (economy mode with L2 escalation)

## Ошибка

- Command: \`${command_display}\`
- Exit code: \`${exit_code}\`
- Symptom: ${primary_error}
- Signature: \`${short_sig}\` (repeat=${repeat_count})

## Анализ 5 Почему

| Уровень | Почему | Ответ |
|---|---|---|
| 1 | Почему упала команда? | Выполнение завершилось ошибкой: ${primary_error} |
| 2 | Почему эта ошибка не была предотвращена заранее? | Не была проверена предпосылка выполнения перед запуском команды |
| 3 | Почему не было предпроверки? | Шаг выполнялся напрямую без обязательного preflight-контроля |
| 4 | Почему workflow позволил это? | Отсутствовал runtime guard на уровне исполнения команды |
| 5 | Почему guard отсутствовал? | Не была формализована и внедрена обязательная обертка для автоперехвата ошибок |

## Корневая причина

Отсутствие обязательного runtime interception для ошибок выполнения и предпроверок перед запуском команды.

## Принятые меры

1. **Немедленное исправление:** Ошибка перехвачена оберткой auto-RCA, зафиксирован инцидент.
2. **Предотвращение:** Использовать \`scripts/auto-rca-wrapper.sh\` для команд, где критична саморефлексия на ошибке.
3. **Документация:** Обновить инструкции и UAT для обязательного auto-RCA trigger.

## Уроки

1. **Runtime guard обязателен** — policy без interception не гарантирует автозапуск RCA.
2. **L1/L2 экономит токены** — краткая саморефлексия по умолчанию, полный RCA по эскалации.
3. **Повтор ошибки = сигнал эскалации** — одинаковые сигнатуры должны переводиться в L2.
EOF

    if [[ "${no_lessons_index}" == true ]]; then
      lessons_status="skipped(no-lessons-index)"
    elif [[ -x "${git_root}/scripts/build-lessons-index.sh" && -x "${git_root}/scripts/query-lessons.sh" ]]; then
      if "${git_root}/scripts/build-lessons-index.sh" >/dev/null 2>&1 && \
         "${git_root}/scripts/query-lessons.sh" --all >/dev/null 2>&1; then
        lessons_status="updated"
      else
        lessons_status="failed"
      fi
    else
      lessons_status="unavailable"
    fi
  fi
fi

{
  echo "AUTO-RCA TRIGGERED"
  echo "Mode: ${mode} (economy)"
  echo "Trigger: command_exit_non_zero"
  echo "Symptom: ${primary_error}"
  echo "Command: ${command_display}"
  echo "Exit code: ${exit_code}"
  echo "Severity: ${severity}"
  echo "Signature: ${short_sig} (repeat=${repeat_count})"
  echo "Q1 Why: Команда завершилась с ошибкой."
  echo "Q2 Why: Предпосылки команды не были проверены до запуска."
  echo "Q3 Why: В шаге не был применен обязательный preflight check."
  echo "Q4 Why: Runtime-перехват ошибок не был enforced на этом вызове."
  echo "Q5 Why: Полагались на policy, а не на технический guard."
  echo "Root cause: Отсутствие обязательного runtime interception на уровне вызова команды."
  echo "Immediate fix: Зафиксировать инцидент и не продолжать без RCA."
  echo "Preventive fix: Выполнять чувствительные команды через auto-rca-wrapper."
  if [[ -n "${rca_report}" ]]; then
    echo "RCA artifact: ${rca_report}"
    echo "Lessons index: ${lessons_status}"
  else
    echo "RCA artifact: L1-only (no docs/rca file); escalate on repeat>=${full_threshold} or severity P0/P1"
  fi
} >&2

exit "${exit_code}"
