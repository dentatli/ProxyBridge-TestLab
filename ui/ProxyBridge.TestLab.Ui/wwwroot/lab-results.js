// Saved measurements only. This view never launches a workload or infers a missing metric.
const resultMetrics = {
  tcp_rtt: [
    ["p50", "rttP50", row => row.mode_metrics?.proxy.p50_ms, 3],
    ["p95", "rttP95", row => row.mode_metrics?.proxy.p95_ms, 3],
    ["p99", "rttP99", row => row.mode_metrics?.proxy.p99_ms, 3],
    ["direct_p50", "directP50", row => row.mode_metrics?.off.p50_ms, 3],
    ["direct_p95", "directP95", row => row.mode_metrics?.off.p95_ms, 3],
    ["direct_p99", "directP99", row => row.mode_metrics?.off.p99_ms, 3],
    // Only the separately validated three-mode scenario supplies UNRULED samples.
    ["unruled_p50", "unruledP50", row => row.mode_metrics?.unruled?.p50_ms, 3],
    ["unruled_p95", "unruledP95", row => row.mode_metrics?.unruled?.p95_ms, 3],
    ["unruled_p99", "unruledP99", row => row.mode_metrics?.unruled?.p99_ms, 3],
    ["added_p95", "addedP95", row => row.paired_addition_ms?.p95_ms, 3],
    ["cpu", "cpuMean", row => row.cli_metrics?.cpu_pct_machine, 3],
    ["ram", "ramMean", row => row.cli_metrics?.private_mib, 2]
  ],
  tcp_transfer: [
    ["upload", "uploadRate", row => row.direction_metrics?.push.proxy_mbit_per_s, 2],
    ["download", "downloadRate", row => row.direction_metrics?.pull.proxy_mbit_per_s, 2],
    ["direct_upload", "directUpload", row => row.direction_metrics?.push.off_mbit_per_s, 2],
    ["direct_download", "directDownload", row => row.direction_metrics?.pull.off_mbit_per_s, 2],
    ["unruled_upload", "unruledUpload", () => null, 2],
    ["unruled_download", "unruledDownload", () => null, 2],
    ["upload_cpu", "uploadCpu", row => row.direction_metrics?.push.cli_cpu_pct_machine, 3],
    ["download_cpu", "downloadCpu", row => row.direction_metrics?.pull.cli_cpu_pct_machine, 3],
    ["upload_ram", "uploadRam", row => row.direction_metrics?.push.cli_private_mib, 2],
    ["download_ram", "downloadRam", row => row.direction_metrics?.pull.cli_private_mib, 2]
  ]
};
resultMetrics.tcp_rtt_three_modes = [...resultMetrics.tcp_rtt,
  ["unruled_added_p95", "unruledAddedP95", row => row.unruled_addition_ms?.p95_ms, 3],
  ["unruled_cpu", "unruledCpu", row => row.unruled_cli_metrics?.cpu_pct_machine, 3],
  ["unruled_ram", "unruledRam", row => row.unruled_cli_metrics?.private_mib, 2]
];
// UNRULED belongs exclusively to the separate three-mode test.
resultMetrics.tcp_rtt = resultMetrics.tcp_rtt.filter(([id]) => !id.startsWith("unruled"));
resultMetrics.tcp_transfer = resultMetrics.tcp_transfer.filter(([id]) => !id.startsWith("unruled"));
function connectionCohort(row, mode, phase = "load") {
  return row.modes?.find(entry => entry.mode === mode)?.cohorts.filter(entry => entry.phase === phase).at(-1);
}
resultMetrics.tcp_connections = [
  ["direct_connections","connectionDirect",row => connectionCohort(row,"OFF")?.confirmed_connections,0],
  ["proxy_connections","connectionProxy",row => connectionCohort(row,"PROXY")?.confirmed_connections,0],
  ["connection_cpu","connectionCpu",row => connectionCohort(row,"PROXY")?.cpu_pct_machine_mean,3],
  ["connection_ram","connectionRam",row => connectionCohort(row,"PROXY")?.private_mib_mean,2],
  ["recovery_connections","recoveryConnections",row => connectionCohort(row,"PROXY","recovery")?.successful_connections,0]
];
const rttResultGroups = [
  ["offGroup", ["direct_p50", "direct_p95", "direct_p99"]],
  ["unruledGroup", ["unruled_p50", "unruled_p95", "unruled_p99", "unruled_cpu", "unruled_ram"]],
  ["proxyGroup", ["p50", "p95", "p99", "cpu", "ram"]],
  ["differenceGroup", ["unruled_added_p95", "added_p95"]]
];
function resultGroups(scenario) {
  const metrics = resultMetrics[scenario];
  return ["tcp_transfer","tcp_connections"].includes(scenario) ? [[null, metrics]] : rttResultGroups.map(([label, ids]) =>
    [label, ids.map(id => metrics.find(metric => metric[0] === id)).filter(Boolean)]);
}
function resultMetricLabel(metric, scenario) {
  if (["tcp_transfer","tcp_connections"].includes(scenario)) return metric[1];
  const id = metric[0];
  if (id.endsWith("p50") || id === "p50") return "latencyP50";
  if (["p95", "direct_p95", "unruled_p95"].includes(id)) return "latencyP95";
  if (id.endsWith("p99") || id === "p99") return "latencyP99";
  if (id === "cpu" || id === "unruled_cpu") return "processCpu";
  if (id === "ram" || id === "unruled_ram") return "processRam";
  return id === "added_p95" ? "proxyDifference" : "unruledDifference";
}
let resultChoices = { builds: null, scenario: "tcp_rtt", workload: "LEGACY", metrics: { tcp_rtt: ["direct_p95", "unruled_p95", "p95", "cpu", "ram"], tcp_transfer: ["direct_upload", "unruled_upload", "upload", "direct_download", "unruled_download", "download", "upload_cpu", "download_cpu", "upload_ram", "download_ram"] } };
resultChoices.metrics.tcp_rtt_three_modes = ["direct_p95", "unruled_p95", "p95", "unruled_added_p95", "unruled_cpu", "cpu", "unruled_ram", "ram"];
resultChoices.metrics.tcp_connections = resultMetrics.tcp_connections.map(metric => metric[0]);
const historyOpen = new Set();
const extraReports = new Map(), extraLaunches = new Map(), detailsLoading = new Set(), detailsErrors = new Set();
let resultEpoch = 0, moreHistoryActive = false;
function resetResultCache() { extraReports.clear(); extraLaunches.clear(); detailsErrors.clear(); resultEpoch++; }

function saveResultChoices() {
  try { sessionStorage.setItem("testlab-result-choices", JSON.stringify(resultChoices)); } catch { }
}
function resultsTab() { return new URL(location.href).searchParams.get("tab") === "history" ? "history" : "compare"; }
function renderResultViews() {
  const tab = resultsTab();
  lab("lab-compare-view").hidden = tab !== "compare";
  lab("lab-history-view").hidden = tab !== "history";
  document.querySelectorAll("[data-results-tab]").forEach(link => {
    if (link.dataset.resultsTab === tab) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
}

function resultRows() {
  const jobs = new Map([...extraLaunches.values(), ...labState.launches].map(job => [job.plan_id, job]));
  const sources = new Map([...labState.localRuns, ...labState.localTransfers, ...labState.localConnections].map(row => [row.id, row]));
  extraReports.forEach((row, id) => { if (!sources.has(id)) sources.set(id, row); });
  const rows = [...sources.values()].map(source => {
    const job = jobs.get(source.build?.plan_id);
    if (!job) return source;
    jobs.delete(job.plan_id);
    return { ...source, terminal: job.terminal, created_at_utc: job.created_at_utc,
      profile: job.profile, workload_preset: job.workload_preset ?? source.workload_preset,
      status: job.status === "COMPLETED" ? source.status : job.status,
      correctness: job.status === "COMPLETED" ? source.correctness : "NOT_CONFIRMED" };
  });
  rows.push(...jobs.values());
  const current = labState.runControl.run;
  if (current) {
    const existing = rows.find(row => row.build?.plan_id === current.planId);
    if (existing && current.status !== "COMPLETED") Object.assign(existing, { status: current.status, terminal: current.terminal, correctness: "NOT_CONFIRMED" });
    else if (!existing && current.buildId && resultMetrics[current.scenario]) rows.push({
      id: "launch-" + current.planId, scenario: current.scenario, profile: current.workloadPreset ? "WORKLOAD" : "SMOKE", workload_preset: current.workloadPreset, contract: "driver",
      created_at_utc: current.startedAtUtc, status: current.status, terminal: current.terminal, correctness: "NOT_CONFIRMED",
      build: { id: current.buildId, name_at_run: current.buildName, plan_id: current.planId }
    });
  }
  return rows.sort((a, b) => new Date(b.created_at_utc) - new Date(a.created_at_utc) || b.id.localeCompare(a.id));
}
function resultBuilds(rows) {
  const builds = new Map();
  rows.forEach(row => { if (row.build?.id && !builds.has(row.build.id)) builds.set(row.build.id, { id: row.build.id, display_name: row.build.name_at_run || row.contract, contract: row.contract }); });
  labState.builds.forEach(build => builds.set(build.id, build));
  return [...builds.values()].sort((a, b) => a.display_name.localeCompare(b.display_name, labLanguage));
}
function resultStatus(row) {
  if (row.not_started) return t("SUITE_TEST_NOT_STARTED");
  if (!row.terminal) return t(row.status) || t("RUNNING");
  if (row.correctness === "PASS") return `${t("localPass")} · ${t("limited")}`;
  return t(row.status) && row.status !== "COMPLETED" ? t(row.status) : t("localNotConfirmed");
}
function renderSavedResults() {
  renderResultViews();
  const rows = resultRows(), builds = resultBuilds(rows);
  if (resultChoices.builds === null && builds.length) {
    resultChoices.builds = labState.observation?.build_id ? [labState.observation.build_id] : builds.slice(0, 2).map(build => build.id);
  }
  lab("comparison-scenario").value = resultChoices.scenario;
  if (!resultChoices.workload) resultChoices.workload = "LEGACY";
  lab("comparison-workload").innerHTML = `<option value="LEGACY">${t("legacyWorkload")}</option>` + ["SHORT","NORMAL","LONG"].flatMap(duration => ["LOW","HIGH"].map(load => `<option value="${duration}:${load}">${t(duration)} · ${t(load)}</option>`)).join("");
  lab("comparison-workload").value = resultChoices.workload;
  lab("comparison-builds").innerHTML = builds.length ? builds.map(build => `<label><input type="checkbox" data-comparison-build="${html(build.id)}" ${(resultChoices.builds || []).includes(build.id) ? "checked" : ""}><span>${html(build.display_name)} (${html(build.contract)})</span></label>`).join("") : `<p>${t("noBuilds")}</p>`;
  lab("comparison-metrics").innerHTML = resultGroups(resultChoices.scenario).filter(([, metrics]) => metrics.length).map(([label, metrics]) =>
    `<div class="lab-metric-group">${label ? `<h3>${t(label)}</h3>` : ""}<div>${metrics.map(metric => `<label><input type="checkbox" data-comparison-metric="${metric[0]}" ${resultChoices.metrics[resultChoices.scenario].includes(metric[0]) ? "checked" : ""}><span>${t(resultMetricLabel(metric, resultChoices.scenario))}</span></label>`).join("")}</div></div>`).join("");
  renderComparison(rows, builds);
  const previous = lab("history-build").value;
  lab("history-build").innerHTML = `<option value="all">${t("allBuilds")}</option>` + builds.map(build => `<option value="${html(build.id)}">${html(build.display_name)} (${html(build.contract)})</option>`).join("");
  if (builds.some(build => build.id === previous)) lab("history-build").value = previous;
  renderHistory(rows);
}
function renderComparison(rows, builds) {
  const output = lab("comparison-table");
  if (labState.resultsUnavailable || labState.launchUnreadable || rows.some(row => row.scenario === resultChoices.scenario && !row.build?.id && row.correctness !== "PASS")) { output.innerHTML = `<p class="lab-warning">${t("latestUnavailable")}</p>`; return; }
  const selected = builds.filter(build => (resultChoices.builds || []).includes(build.id));
  const metrics = resultMetrics[resultChoices.scenario].filter(([id]) => resultChoices.metrics[resultChoices.scenario].includes(id));
  if (!selected.length || !metrics.length) { output.innerHTML = `<p>${t("selectComparison")}</p>`; return; }
  const latest = selected.map(build => rows.find(row => row.build?.id === build.id && row.scenario === resultChoices.scenario && (row.workload_preset ? `${row.workload_preset.duration}:${row.workload_preset.load}` : "LEGACY") === resultChoices.workload));
  latest.forEach(row => { if (row?.terminal && row.status === "COMPLETED" && row.evidence_id && row.id.startsWith("launch-")) loadHistoryDetails(row.evidence_id); });
  const columns = selected.map((build, index) => {
    const row = latest[index];
    return `<th>${html(build.display_name)}<div class="lab-comparison-stamp">${row ? html(new Date(row.created_at_utc).toLocaleString(labLanguage)) : t("noMeasurements")}</div><div class="lab-comparison-stamp">${row ? html(row.evidence_id && detailsLoading.has(row.evidence_id) ? t("checking") : resultStatus(row)) : ""}</div></th>`;
  }).join("");
  const body = resultGroups(resultChoices.scenario).map(([label, groupMetrics]) => {
    const selectedMetrics = groupMetrics.filter(metric => metrics.includes(metric));
    if (!selectedMetrics.length) return "";
    const heading = label ? `<tr class="lab-metric-heading"><th colspan="${selected.length + 1}">${t(label)}</th></tr>` : "";
    return heading + selectedMetrics.map(metric => {
      const [, , value, digits] = metric;
      return `<tr><th scope="row">${t(resultMetricLabel(metric, resultChoices.scenario))}</th>${latest.map(row => `<td>${row?.terminal && row.correctness === "PASS" ? number(value(row), digits) : "—"}</td>`).join("")}</tr>`;
    }).join("");
  }).join("");
  const keys = new Set(latest.filter(row => row?.correctness === "PASS").map(row => row.conditions_key || "unknown"));
  const warning = keys.size > 1 || keys.has("unknown") ? `<p class="lab-warning">${t("conditionsDiffer")}</p>` : "";
  const active = labState.runControl.run;
  const activeNote = active && !active.terminal && active.scenario === resultChoices.scenario && selected.some(build => build.id === active.buildId) ? `<p>${t("newMeasurementRunning")}</p>` : "";
  const rtt = ["tcp_rtt","tcp_rtt_three_modes"].includes(resultChoices.scenario);
  const help = rtt ? `<p>${t("latencyHelp")}</p><p>${t("resourceHelp")}</p>` : "";
  const conditions = resultChoices.workload !== "LEGACY" ? `<p>${html(workloadName({duration: resultChoices.workload.split(":")[0], load: resultChoices.workload.split(":")[1]}))}</p><p>${html(workloadDescription(resultChoices.scenario, {duration: resultChoices.workload.split(":")[0], load: resultChoices.workload.split(":")[1]}))}</p><p>${t("workloadScope")}</p>` : `<p>${t(resultChoices.scenario === "tcp_rtt_three_modes" ? "threeModesConditions" : resultChoices.scenario === "tcp_rtt" ? "shortRttConditions" : "shortTransferConditions")}</p><p>${t(resultChoices.scenario === "tcp_rtt_three_modes" ? "threeModesScope" : "directModesHelp")}</p>`;
  output.innerHTML = `${help}${activeNote}<div class="lab-table-scroll"><table><thead><tr><th>${t("metric")}</th>${columns}</tr></thead><tbody>${body}</tbody></table></div>${rtt ? `<p>${t("differenceHelp")}</p>` : resultChoices.scenario === "tcp_connections" ? `<p>${t("connectionScope")}</p>` : ""}<details><summary>${t("measurementConditions")}</summary>${conditions}</details>${warning}`;
}
function renderHistory(rows = resultRows()) {
  const build = lab("history-build").value, scenario = lab("history-scenario").value, status = lab("history-status").value;
  const matches = row => {
    if (build !== "all" && row.build?.id !== build || scenario !== "all" && row.scenario !== scenario) return false;
    if (status === "all") return true;
    if (status === "running") return !row.terminal;
    if (status === "cancelled") return row.status === "CANCELLED";
    if (status === "completed") return row.correctness === "PASS" && row.terminal;
    return row.terminal && row.correctness !== "PASS" && row.status !== "CANCELLED";
  };
  const filtered = rows.filter(matches);
  lab("history-count").textContent = `${t("historyShown")}: ${number(filtered.length, 0)} / ${number(rows.length, 0)}`;
  const warning = labState.localUnreadable || labState.transferUnreadable || labState.connectionUnreadable || labState.launchUnreadable ? `<p class="lab-warning">${t("historyIncomplete")}</p>` : "";
  lab("lab-test-history").innerHTML = labState.resultsUnavailable ? `<p>${t("unavailable")}</p>` : filtered.map(row => {
    const name = testTitle(row.scenario);
    const details = row.scenario === "tcp_connections" && !row.id.startsWith("launch-") ? localConnectionMarkup(row) : row.mode_metrics ? localRunMarkup(row) : row.direction_metrics ? localTransferMarkup(row) : `<p>${row.evidence_id && detailsLoading.has(row.evidence_id) ? t("checking") : t("noConfirmedDetails")}</p>`;
    return `<details class="lab-history-entry" data-history-id="${html(row.id)}" ${row.terminal && row.evidence_id ? `data-evidence-id="${html(row.evidence_id)}"` : ""} ${historyOpen.has(row.id) ? "open" : ""}><summary>${html(reportBuildName(row))} · ${name} · ${html(workloadName(row.workload_preset))}<small>${html(new Date(row.created_at_utc).toLocaleString(labLanguage))} · ${html(resultStatus(row))}</small></summary>${details}</details>`;
  }).join("") + warning || `<p>${t("noHistoryMatches")}</p>`;
  lab("history-more").hidden = labState.launchNextOffset === null;
  lab("history-more").disabled = moreHistoryActive;
}
async function loadHistoryDetails(id) {
  if (detailsLoading.has(id) || detailsErrors.has(id) || extraReports.has(id) || !/^(lab-tcp_(rtt|transfer|connections|rtt_three_modes)-smoke-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}|tcp-rtt-three-modes-smoke-[0-9]{8}-[0-9]{6}-[a-f0-9]{6})$/.test(id)) return;
  if ([...labState.localRuns, ...labState.localTransfers, ...labState.localConnections].some(row => row.id === id)) return;
  const epoch = resultEpoch;
  const keepOpen = resultRows().some(row => row.evidence_id === id && historyOpen.has(row.id));
  detailsLoading.add(id);
  try {
    const response = await fetch(`/api/v1/lab/history/${encodeURIComponent(id)}`, { cache: "no-store", signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("history-detail");
    const data = await response.json(), row = data.items?.find(item => item.id === id);
    if (!row) throw new Error("history-detail");
    if (epoch === resultEpoch) { extraReports.set(id, row); if (keepOpen) historyOpen.add(row.id); }
  } catch { if (epoch === resultEpoch) detailsErrors.add(id); }
  finally { detailsLoading.delete(id); }
  renderSavedResults();
}
async function moreHistory() {
  if (moreHistoryActive || labState.launchNextOffset === null) return;
  const epoch = resultEpoch, offset = labState.launchNextOffset;
  moreHistoryActive = true; renderHistory();
  try {
    const response = await fetch(`/api/v1/lab/history?offset=${offset}`, { cache: "no-store", signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("history-page");
    const data = await response.json();
    if (epoch === resultEpoch) {
      data.items.forEach(row => extraLaunches.set(row.plan_id, row));
      labState.launchNextOffset = data.next_offset ?? null;
      labState.launchUnreadable += data.unreadable || 0;
    }
  } catch { if (epoch === resultEpoch) labState.launchUnreadable++; }
  finally { moreHistoryActive = false; renderSavedResults(); }
}
function setupResults() {
  lab("comparison-workload").addEventListener("change", () => {
    resultChoices.workload = lab("comparison-workload").value;
    saveResultChoices(); renderSavedResults();
  });
  try {
    const saved = JSON.parse(sessionStorage.getItem("testlab-result-choices") || "null");
    if (saved && Object.hasOwn(resultMetrics, saved.scenario)) {
      resultChoices.scenario = saved.scenario;
      if (typeof saved.workload === "string" && /^(LEGACY|(SHORT|NORMAL|LONG):(LOW|HIGH))$/.test(saved.workload)) resultChoices.workload = saved.workload;
      if (Array.isArray(saved.builds)) resultChoices.builds = saved.builds.filter(id => typeof id === "string" && /^build-[a-f0-9]{64}$/.test(id));
      for (const scenario of Object.keys(resultMetrics))
        if (Array.isArray(saved.metrics?.[scenario])) resultChoices.metrics[scenario] = saved.metrics[scenario].filter(id => resultMetrics[scenario].some(metric => metric[0] === id));
    }
  } catch { }
  document.querySelectorAll("[data-results-tab]").forEach(link => link.addEventListener("click", event => {
    if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    const url = new URL(location.href);
    url.searchParams.set("page", "results"); url.searchParams.set("tab", link.dataset.resultsTab);
    if (url.href !== location.href) history.pushState(null, "", url);
    renderResultViews();
  }));
  lab("comparison-scenario").addEventListener("change", () => { resultChoices.scenario = lab("comparison-scenario").value; saveResultChoices(); renderSavedResults(); });
  lab("comparison-builds").addEventListener("change", () => { resultChoices.builds = [...document.querySelectorAll("[data-comparison-build]:checked")].map(node => node.dataset.comparisonBuild); saveResultChoices(); renderComparison(resultRows(), resultBuilds(resultRows())); });
  lab("comparison-metrics").addEventListener("change", () => { resultChoices.metrics[resultChoices.scenario] = [...document.querySelectorAll("[data-comparison-metric]:checked")].map(node => node.dataset.comparisonMetric); saveResultChoices(); renderComparison(resultRows(), resultBuilds(resultRows())); });
  for (const id of ["history-build", "history-scenario", "history-status"]) lab(id).addEventListener("change", () => renderHistory());
  lab("lab-test-history").addEventListener("toggle", event => {
    const node = event.target;
    if (!node.isConnected || !node.matches("details[data-history-id]")) return;
    if (node.open) { historyOpen.add(node.dataset.historyId); if (node.dataset.evidenceId) loadHistoryDetails(node.dataset.evidenceId); }
    else historyOpen.delete(node.dataset.historyId);
  }, true);
  lab("history-more").addEventListener("click", moreHistory);
}
