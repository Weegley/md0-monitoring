const TAIL_LINES = 80;
let autoRefreshTimer = null;

const I18N = {
  en: {
    htmlLang: "en",
    pageTitle: "RAID Tools",
    titleMain: "RAID Tools",
    subtitleMain: "md0, SMART and RAID script logs",
    labelAutoRefresh: "auto refresh every 30s",
    titleActions: "Actions",
    actionReady: "Ready",
    hintLogsFallback: "If today's log does not exist yet, the latest available log will be used.",
    btnRefreshAll: "Refresh all",
    btnRunCheck: "Run check_raid.sh",
    btnRunScrub: "Run raid_scrub_bg.sh",
    btnStopScrub: "Stop scrub",
    btnRunCleanup: "Clean old logs",
    btnRefreshLogs: "Refresh logs only",
    btnRefresh: "Refresh",
    titleMdadmStatus: "mdadm status",
    titleLastSmart: ".last_smart",
    titleLogMd0: "md0 log — latest lines",
    titleLogScrub: "scrub log — latest lines",
    titleLogSmart: "smart log — latest lines",
    loading: "Loading...",
    empty: "No output",
    fileNotFound: "Log file not found",
    source: "Source",
    sourceUnknown: "Source unknown",
    readError: "Read error",
    ready: "Ready",
    done: "done",
    error: "error",
    running: "running",
    noLogsFound: kind => `No ${kind} logs found`,
    lastSmartNotFound: ".last_smart not found",
    actionDone: title => `${title}: done`,
  },
  ru: {
    htmlLang: "ru",
    pageTitle: "RAID Tools",
    titleMain: "RAID Tools",
    subtitleMain: "md0, SMART и журналы RAID-скриптов",
    labelAutoRefresh: "автообновление 30с",
    titleActions: "Действия",
    actionReady: "Готово",
    hintLogsFallback: "Если лог за сегодня ещё не создан, подхватится последний существующий файл.",
    btnRefreshAll: "Обновить всё",
    btnRunCheck: "Запустить check_raid.sh",
    btnRunScrub: "Запустить raid_scrub_bg.sh",
    btnStopScrub: "Остановить scrub",
    btnRunCleanup: "Очистить старые логи",
    btnRefreshLogs: "Обновить только логи",
    btnRefresh: "Обновить",
    titleMdadmStatus: "Статус mdadm",
    titleLastSmart: ".last_smart",
    titleLogMd0: "md0 log — последние строки",
    titleLogScrub: "scrub log — последние строки",
    titleLogSmart: "smart log — последние строки",
    loading: "Загрузка...",
    empty: "Пустой вывод",
    fileNotFound: "Файл лога не найден",
    source: "Источник",
    sourceUnknown: "Источник не определён",
    readError: "Ошибка чтения",
    ready: "Готово",
    done: "готово",
    error: "ошибка",
    running: "выполняется",
    noLogsFound: kind => `Логи ${kind} не найдены`,
    lastSmartNotFound: ".last_smart не найден",
    actionDone: title => `${title}: выполнено`,
  }
};

function detectLanguage() {
  let parentLang = "";
  try {
    parentLang =
      window.parent &&
      window.parent !== window &&
      window.parent.document &&
      window.parent.document.documentElement
        ? window.parent.document.documentElement.lang || ""
        : "";
  } catch (e) {
    parentLang = "";
  }

  const lang =
    parentLang ||
    ((typeof cockpit !== "undefined" && cockpit.language) ? cockpit.language : "") ||
    navigator.language ||
    "en";

  return String(lang).toLowerCase().startsWith("ru") ? "ru" : "en";
}

const LANG = detectLanguage();
const T = I18N[LANG];

function applyTranslations() {
  document.documentElement.lang = T.htmlLang;
  document.title = T.pageTitle;

  const map = {
    "title-main": T.titleMain,
    "subtitle-main": T.subtitleMain,
    "label-auto-refresh": T.labelAutoRefresh,
    "title-actions": T.titleActions,
    "title-mdadm-status": T.titleMdadmStatus,
    "title-last-smart": T.titleLastSmart,
    "title-log-md0": T.titleLogMd0,
    "title-log-scrub": T.titleLogScrub,
    "title-log-smart": T.titleLogSmart,
    "refresh-all": T.btnRefreshAll,
    "run-check": T.btnRunCheck,
    "run-scrub": T.btnRunScrub,
    "stop-scrub": T.btnStopScrub,
    "run-cleanup": T.btnRunCleanup,
    "refresh-logs": T.btnRefreshLogs,
    "refresh-status": T.btnRefresh,
    "refresh-last-smart": T.btnRefresh,
    "hint-logs-fallback": T.hintLogsFallback,
    "action-status": T.actionReady,
    "mdadm-status": T.loading,
    "last-smart": T.loading,
    "meta-md0": T.loading,
    "meta-scrub": T.loading,
    "meta-smart": T.loading,
    "log-md0": T.loading,
    "log-scrub": T.loading,
    "log-smart": T.loading,
  };

  for (const [id, value] of Object.entries(map)) {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  document.querySelectorAll('button[data-log]').forEach(btn => {
    btn.textContent = T.btnRefresh;
  });
}

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
    setText("mdadm-status", out || T.empty);
  } catch (e) {
    setText("mdadm-status", formatError(e));
  }
}

async function loadLastSmart() {
  try {
    const out = await run([
      "bash", "-lc",
      `if [ -f /var/log/raid/.last_smart ]; then cat /var/log/raid/.last_smart; else echo '${T.lastSmartNotFound}'; fi`
    ]);
    setText("last-smart", out || T.empty);
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
    echo "${T.noLogsFound("__KIND__")}"
  fi
fi
`.replaceAll("__KIND__", kind).trim();

  try {
    const out = await run(["bash", "-lc", script]);
    const lines = (out || "").split("\n");
    const first = lines.shift() || "";
    const body = lines.join("\n");

    if (first.startsWith("__FILE__:")) {
      const file = first.slice("__FILE__:".length);
      if (file === "missing") {
        setText(meta, T.fileNotFound);
      } else {
        setText(meta, `${T.source}: ${file}`);
      }
    } else {
      setText(meta, T.sourceUnknown);
    }

    setText(target, body || T.empty);
    scrollLogToBottom(target);
  } catch (e) {
    setText(meta, T.readError);
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
    setActionStatus(`${title}: ${T.done}`, "ok");
    await refreshAll();
    showMessage(out || T.actionDone(title));
  } catch (e) {
    setActionStatus(`${title}: ${T.error}`, "err");
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
  applyTranslations();
  setupButtons();
  setupAutoRefresh();
  await refreshAll();
  setActionStatus(T.ready, "ok");
}

init().catch(err => {
  setActionStatus(T.error, "err");
  showMessage(formatError(err));
});
