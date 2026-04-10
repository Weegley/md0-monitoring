const TAIL_LINES = 80;
let autoRefreshTimer = null;

function setText(id, text) {
  document.getElementById(id).textContent = text;
}

function scrollLogToBottom(id) {
  const el = document.getElementById(id);
  if (!el) return;
  requestAnimationFrame(() => {
    el.scrollTop = el.scrollHeight;
  });
}

function setActionStatus(text, cls = "muted") {
  const el = document.getElementById("action-status");
  el.textContent = text;
  el.className = cls;
}

function showMessage(msg) {
  if (msg && msg.trim()) window.alert(msg);
}

function run(args, opts = {}) {
  return cockpit.spawn(args, {
    superuser: "require",
    err: "message",
    ...opts,
  });
}

function formatError(e) {
  const parts = [];
  if (e?.message) parts.push(`message: ${e.message}`);
  if (e?.problem) parts.push(`problem: ${e.problem}`);
  if (e?.exit_status !== undefined && e?.exit_status !== null) parts.push(`exit_status: ${e.exit_status}`);
  if (e?.exit_signal) parts.push(`exit_signal: ${e.exit_signal}`);
  return parts.length ? parts.join("\n") : String(e);
}

async function loadMdadmStatus() {
  try {
    const out = await run(["mdadm", "--detail", "/dev/md0"]);
    setText("mdadm-status", out || "Пустой вывод");
  } catch (e) {
    setText("mdadm-status", formatError(e));
  }
}

async function loadLastSmart() {
  try {
    const out = await run([
      "bash", "-lc",
      "if [ -f /var/log/raid/.last_smart ]; then cat /var/log/raid/.last_smart; else echo '.last_smart not found'; fi"
    ]);
    setText("last-smart", out || "Пустой вывод");
  } catch (e) {
    setText("last-smart", formatError(e));
  }
}

async function loadLog(kind) {
  const target = `log-${kind}`;
  const meta = `meta-${kind}`;

  const script = `
today=$(date +%F)
today_file="/var/log/raid/${kind}_$today.log"
if [ -f "$today_file" ]; then
  echo "__FILE__:$today_file"
  tail -n ${TAIL_LINES} "$today_file"
else
  latest=$(ls -1t /var/log/raid/${kind}_*.log 2>/dev/null | head -n 1)
  if [ -n "$latest" ]; then
    echo "__FILE__:$latest"
    tail -n ${TAIL_LINES} "$latest"
  else
    echo "__FILE__:missing"
    echo "No ${kind} logs found"
  fi
fi
`.trim();

  try {
    const out = await run(["bash", "-lc", script]);
    const lines = (out || "").split("\n");
    const first = lines.shift() || "";
    const body = lines.join("\n");

    if (first.startsWith("__FILE__:")) {
      const file = first.slice("__FILE__:".length);
      if (file === "missing") {
        setText(meta, "Файл лога не найден");
      } else {
        setText(meta, `Источник: ${file}`);
      }
    } else {
      setText(meta, "Источник не определён");
    }

    setText(target, body || "Пустой вывод");
    scrollLogToBottom(target);
  } catch (e) {
    setText(meta, "Ошибка чтения");
    setText(target, formatError(e));
    scrollLogToBottom(target);
  }
}

async function loadAllLogs() {
  await Promise.all([loadLog("md0"), loadLog("smart"), loadLog("scrub")]);
}

async function refreshAll() {
  await Promise.all([loadMdadmStatus(), loadLastSmart(), loadAllLogs()]);
}

async function runAction(title, args) {
  setActionStatus(`${title}...`, "warn");
  try {
    const out = await run(args);
    setActionStatus(`${title}: готово`, "ok");
    await refreshAll();
    showMessage(out || `${title}: выполнено`);
  } catch (e) {
    setActionStatus(`${title}: ошибка`, "err");
    showMessage(formatError(e));
    await refreshAll();
  }
}

function setupButtons() {
  document.getElementById("refresh-all").addEventListener("click", refreshAll);
  document.getElementById("refresh-logs").addEventListener("click", loadAllLogs);
  document.getElementById("refresh-status").addEventListener("click", loadMdadmStatus);
  document.getElementById("refresh-last-smart").addEventListener("click", loadLastSmart);

  document.getElementById("run-check").addEventListener("click", () =>
    runAction("check_raid.sh", ["/usr/local/sbin/check_raid.sh"])
  );

  document.getElementById("run-scrub").addEventListener("click", () =>
    runAction("raid_scrub_bg.sh", ["/usr/local/sbin/raid_scrub_bg.sh"])
  );

  document.getElementById("stop-scrub").addEventListener("click", () =>
    runAction("scrub_stop.sh", ["/usr/local/sbin/scrub_stop.sh"])
  );

  document.getElementById("run-cleanup").addEventListener("click", () =>
    runAction("cleanup_raid_logs.sh", ["/usr/local/sbin/cleanup_raid_logs.sh"])
  );

  document.querySelectorAll("button[data-log]").forEach(btn => {
    btn.addEventListener("click", () => loadLog(btn.dataset.log));
  });

  document.getElementById("auto-refresh").addEventListener("change", setupAutoRefresh);
}

function setupAutoRefresh() {
  if (autoRefreshTimer) {
    clearInterval(autoRefreshTimer);
    autoRefreshTimer = null;
  }
  if (document.getElementById("auto-refresh").checked) {
    autoRefreshTimer = setInterval(() => {
      loadMdadmStatus();
      loadLastSmart();
      loadAllLogs();
    }, 30000);
  }
}

async function init() {
  setupButtons();
  setupAutoRefresh();
  await refreshAll();
  setActionStatus("Готово", "ok");
}

init().catch(err => {
  setActionStatus("Ошибка инициализации", "err");
  showMessage(formatError(err));
});
