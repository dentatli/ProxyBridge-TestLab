const state = {
  catalog: [], jobs: [], reports: [], settingsSchema: null, settingsView: null, settingsSection: "local_product",
  csrfToken: "", serverStatus: null, serverValidation: null, serverPlan: null, realRuntimeAvailable: false,
  runSelection: new Set(), runPreparation: null, activeJob: null, runPollTimer: null, runVisible: []
};

const escapeHtml = (value) => String(value ?? "")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

const statusClass = (status) => {
  if (status === "DECLARATIVE_ONLY") return "declarative";
  if (status === "SYSTEM_CHECK") return "system-check";
  if (status === "CAPABILITY_GATED") return "capability-gated";
  if (status === "UNSUPPORTED_PRODUCT_SCOPE") return "unsupported";
  if (["FAIL_PRODUCT", "FAIL_HARNESS", "FAIL_INFRASTRUCTURE", "CONTAMINATED", "SAFETY_STOPPED", "FAILED_TO_START"].includes(status)) return "failure";
  if (["EXPECTED_FAIL", "MOCK_EXPECTED_FAIL", "HOLD_AMBIGUOUS", "MOCK_HOLD"].includes(status)) return "expected";
  return "";
};

const showToast = (message) => {
  const toast = document.querySelector("#toast");
  toast.textContent = message;
  toast.classList.add("show");
  window.setTimeout(() => toast.classList.remove("show"), 3500);
};

function beginButtonAction(button, busyText) {
  if (!button || button.dataset.busy === "true") return false;
  button.dataset.busy = "true";
  button.dataset.idleText = button.textContent;
  button.setAttribute("aria-busy", "true");
  button.disabled = true;
  button.textContent = busyText;
  return true;
}

function endButtonAction(button, disabled = false, text = null) {
  if (!button) return;
  button.textContent = text ?? button.dataset.idleText ?? button.textContent;
  button.disabled = disabled;
  button.removeAttribute("aria-busy");
  delete button.dataset.busy;
  delete button.dataset.idleText;
}

const advancedSettingsSections = new Set(["timeouts", "retention", "ui"]);
const advancedSettingFields = new Set([
  "local_product.service_name",
  "proxy.port", "proxy.config_id",
  "server_connection.ssh_port",
  "server_endpoint.port_a", "server_endpoint.port_b"
]);

async function getJson(url) {
  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

function switchView(view) {
  document.querySelectorAll(".view").forEach((node) => node.classList.toggle("active", node.id === `${view}-view`));
  document.querySelectorAll(".nav-item[data-view]").forEach((node) => node.classList.toggle("active", node.dataset.view === view));
  const titles = { dashboard: "System overview", catalog: "Test catalog", run: "Run tests", results: "Run results", settings: "Environment setup", server: "Server setup" };
  document.querySelector("#page-title").textContent = titles[view];
  window.location.hash = view;
}

function renderCatalog() {
  const query = document.querySelector("#catalog-search").value.trim().toLowerCase();
  const protocol = document.querySelector("#filter-protocol").value;
  const family = document.querySelector("#filter-family").value;
  const action = document.querySelector("#filter-action").value;
  const status = document.querySelector("#filter-status").value;

  const items = state.catalog.filter((item) =>
    (!query || item.scenario_id.toLowerCase().includes(query) || item.title.toLowerCase().includes(query) || item.tags.some((tag) => tag.toLowerCase().includes(query))) &&
    (!protocol || item.protocol === protocol) &&
    (!family || String(item.family) === family) &&
    (!action || item.action === action) &&
    (!status || item.implementation_status === status));

  const groups = new Map();
  state.catalog.forEach((item) => {
    const current = groups.get(item.coverage_group) || { declared: 0, executable: 0, planned: 0, systemChecks: 0, gated: 0, unsupported: 0 };
    current.declared += 1;
    if (item.implementation_status === "EXECUTABLE") current.executable += 1;
    else if (item.implementation_status === "DECLARATIVE_ONLY") current.planned += 1;
    else if (item.implementation_status === "SYSTEM_CHECK") current.systemChecks += 1;
    else if (item.implementation_status === "CAPABILITY_GATED") current.gated += 1;
    else current.unsupported += 1;
    groups.set(item.coverage_group, current);
  });
  document.querySelector("#catalog-coverage-matrix").innerHTML = [...groups.entries()].sort(([left], [right]) => left.localeCompare(right)).map(([name, counts]) => `
    <div class="coverage-group"><strong>${escapeHtml(name)}</strong><span>${counts.executable} executable</span><small>${counts.planned} planned · ${counts.systemChecks} system · ${counts.gated} gated · ${counts.unsupported} unsupported · ${counts.declared} total</small></div>`).join("");

  document.querySelector("#catalog-count").textContent = `${items.length} of ${state.catalog.length} scenarios`;
  const list = document.querySelector("#catalog-list");
  if (!items.length) {
    list.innerHTML = '<div class="empty">No scenarios match the current filters.</div>';
    return;
  }

  list.innerHTML = items.map((item) => `
    <details class="scenario">
      <summary>
        <div class="scenario-title"><strong>${escapeHtml(item.scenario_id)}</strong><small>${escapeHtml(item.title)}</small></div>
        <div class="data-cell"><span>Protocol</span><strong>${escapeHtml(item.protocol)} / IPv${item.family}</strong></div>
        <div class="data-cell"><span>Action</span><strong>${escapeHtml(item.action)}</strong></div>
        <div class="data-cell"><span>Group</span><strong>${escapeHtml(item.coverage_group)}</strong></div>
        <div class="data-cell"><span>Contract</span><strong class="status-text ${statusClass(item.implementation_status)}">${escapeHtml(item.implementation_status)}</strong></div>
        <div class="chevron">＋</div>
      </summary>
      <div class="detail-body">
        <div class="detail-grid">
          <div class="detail-block"><h3>Purpose</h3><p>${escapeHtml(item.title)}. The runner evaluates ${escapeHtml(item.protocol)} IPv${item.family} traffic expected to follow the ${escapeHtml(item.action)} path.</p></div>
          <div class="detail-block"><h3>Prerequisites</h3><div class="tags">${item.requires.map((entry) => `<span class="tag">${escapeHtml(entry)}</span>`).join("")}</div></div>
          <div class="detail-block"><h3>Evidence contract</h3><p>Profile: ${escapeHtml(item.evidence_profile_id)}</p><ul>${item.assertions.map((entry) => `<li>${escapeHtml(entry)}</li>`).join("")}</ul></div>
          <div class="detail-block"><h3>Execution</h3><p>Executor: ${escapeHtml(item.executor_kind)}${item.protocol_family ? `<br>Family: ${escapeHtml(item.protocol_family)}` : ""}<br>Socket: ${escapeHtml(item.socket_mode)}<br>Reset: ${escapeHtml(item.reset_policy)}<br>Independent: ${item.independent ? "Yes" : "No"}</p></div>
          <div class="detail-block"><h3>Implementation</h3><p>${item.implementation_reason ? escapeHtml(item.implementation_reason) : "Executable contract is present."}</p></div>
          <div class="detail-block"><h3>Coverage authority</h3><p>${item.implementation_status === "EXECUTABLE" ? "The client and evidence contract can produce a real verdict when every readiness gate passes." : item.implementation_status === "SYSTEM_CHECK" ? "The controller enforces this check across real attempts; it is not a separate product-traffic verdict." : item.implementation_status === "CAPABILITY_GATED" ? "This coverage is resolved but remains unavailable until its explicit topology or product-contract capability exists." : "This entry documents a required class but cannot produce a real product verdict with the current client/evidence contract."}</p></div>
          <div class="detail-block"><h3>Known defect</h3><p>${item.known_defect ? `<strong>${escapeHtml(item.known_defect.id)}</strong><br>${escapeHtml(item.known_defect.reason)}` : "No catalog mapping."}</p></div>
        </div>
      </div>
    </details>`).join("");
}

function resultExplanation(result) {
  const prefix = result.run_mode === "real" ? "A real runtime record" : "A fixture or mock record";
  return `${prefix} was classified as ${result.status}. ${result.reason} The displayed status comes from the runner report; this UI does not recalculate the verdict.`;
}

async function loadResultDetail(button, runId, scenarioId) {
  const row = button.closest(".result-row");
  row.classList.toggle("open");
  const target = row.querySelector(".result-detail");
  if (!row.classList.contains("open") || target.dataset.loaded === "true") return;
  target.innerHTML = '<div class="empty">Loading sanitized evidence…</div>';
  try {
    const detail = await getJson(`/api/v1/runs/${encodeURIComponent(runId)}/scenarios/${encodeURIComponent(scenarioId)}`);
    target.dataset.loaded = "true";
    const explanation = detail.explanation;
    const errorGroup = (title, values, cssClass = "") => values.length ? `<div class="explanation-block ${cssClass}"><h4>${escapeHtml(title)}</h4><ul>${values.map((value) => `<li>${escapeHtml(value)}</li>`).join("")}</ul></div>` : "";
    target.innerHTML = `
      <div class="explanation result-explanation">
        <div class="explanation-heading"><div><span class="tag">${escapeHtml(explanation.category)}</span><h3>${escapeHtml(explanation.summary)}</h3></div><span class="status-text ${statusClass(detail.result.status)}">${escapeHtml(detail.result.status)}</span></div>
        <div class="explanation-grid">
          <div class="explanation-block"><h4>What was tested</h4><p>${escapeHtml(explanation.whatWasTested)}</p></div>
          <div class="explanation-block"><h4>Expected</h4><p>${escapeHtml(explanation.expected)}</p></div>
          <div class="explanation-block"><h4>Observed</h4><p>${escapeHtml(explanation.observed)}</p></div>
          <div class="explanation-block"><h4>Why this status</h4><p>${escapeHtml(explanation.why)}</p></div>
          <div class="explanation-block next-action"><h4>Recommended next action</h4><p>${escapeHtml(explanation.nextAction)}</p></div>
          <div class="explanation-block"><h4>Evidence basis</h4><p>${escapeHtml(explanation.evidenceBasis)}</p></div>
        </div>
        <div class="error-groups">
          ${errorGroup("Product errors", explanation.productErrors, "product")}
          ${errorGroup("Harness / infrastructure errors", explanation.harnessErrors, "harness")}
          ${errorGroup("Missing evidence", explanation.missingEvidence, "missing")}
          ${errorGroup("Contamination", explanation.contamination, "contamination")}
        </div>
      </div>
      <details class="evidence-section" open><summary>Assertion timeline and evidence channels <span>＋</span></summary><div class="evidence-section-body">
        <div class="timeline-list">${explanation.timeline.map((entry) => `<div class="timeline-entry ${entry.state === "RECORDED" ? "recorded" : "missing"}"><span>${String(entry.order).padStart(2, "0")}</span><div><strong>${escapeHtml(entry.step)}</strong><small>${escapeHtml(entry.state)} · ${escapeHtml(entry.detail)}</small></div></div>`).join("")}</div>
        <div class="channel-list">${explanation.channels.map((channel) => `<div class="channel-entry"><strong>${escapeHtml(channel.name)}</strong><span class="status-text ${channel.state === "RECORDED" ? "" : "expected"}">${escapeHtml(channel.state)}</span><small>${escapeHtml(channel.detail)}</small></div>`).join("")}</div>
      </div></details>
      <details class="evidence-section"><summary>Sanitized technical evidence <span>＋</span></summary><div class="evidence-section-body artifact-list">
        ${Object.entries(detail.evidence).map(([name, value]) => `<details class="artifact"><summary>${escapeHtml(name)} <span>＋</span></summary><pre>${escapeHtml(JSON.stringify(value, null, 2))}</pre></details>`).join("") || '<div class="empty">No allowed structured evidence artifacts are available.</div>'}
      </div></details>
      <p class="authority-note">${escapeHtml(resultExplanation(detail.result))}</p>`;
  } catch (error) {
    target.innerHTML = `<div class="error">Evidence could not be loaded: ${escapeHtml(error.message)}</div>`;
  }
}

async function openRun(details, runId) {
  if (!details.open || details.dataset.loaded === "true") return;
  const target = details.querySelector(".run-body");
  target.innerHTML = '<div class="empty">Loading report…</div>';
  try {
    const data = await getJson(`/api/v1/runs/${encodeURIComponent(runId)}`);
    details.dataset.loaded = "true";
    const jobSummary = data.job ? `
      <div class="explanation"><h3>${escapeHtml(data.job.state)} · ${escapeHtml(data.job.mode)}</h3><p>${escapeHtml(data.job.terminalReason || `Current phase: ${data.job.currentPhase}. ${data.job.completedCount} of ${data.job.selectedCount} selected tests have a recorded disposition.`)}</p></div>` : "";
    const exportButton = (data.run || data.job?.evidenceRunId) ? `<a class="button secondary audit-download" href="/api/v1/runs/${encodeURIComponent(runId)}/export" download>Download sanitized audit ZIP</a>` : "";
    target.innerHTML = `${jobSummary}${exportButton}<div class="run-results">${data.results.map((result) => `
      <div class="result-row">
        <button class="result-header" data-run="${escapeHtml(runId)}" data-scenario="${escapeHtml(result.scenario_id)}">
          <strong>${escapeHtml(result.scenario_id)}</strong>
          <strong class="status-text ${statusClass(result.status)}">${escapeHtml(result.status)}</strong>
          <span>${result.duration_ms} ms</span>
        </button>
        <div class="result-detail"></div>
      </div>`).join("") || `<div class="empty">${data.job?.terminal ? "No complete runner report is linked to this job." : "This run is still in progress."}</div>`}</div>`;
    target.querySelectorAll(".result-header").forEach((button) => button.addEventListener("click", () => loadResultDetail(button, button.dataset.run, button.dataset.scenario)));
  } catch (error) {
    target.innerHTML = `<div class="error">Report could not be loaded: ${escapeHtml(error.message)}</div>`;
  }
}

function renderRuns() {
  const list = document.querySelector("#runs-list");
  const linkedEvidence = new Set(state.jobs.map((job) => job.evidenceRunId).filter(Boolean));
  const reports = state.reports.filter((run) => !linkedEvidence.has(run.runId));
  if (!state.jobs.length && !reports.length) {
    list.innerHTML = '<div class="empty">No sanitized reports are available yet.</div>';
    return;
  }

  const jobCards = state.jobs.map((job) => `
    <details class="run-card" data-run-id="${escapeHtml(job.runId)}">
      <summary>
        <div class="scenario-title"><strong>${escapeHtml(job.runId)}</strong><small>${job.mode === "mock" ? "Fixture preview" : "Guarded real run"} · controller job</small></div>
        <div class="data-cell"><span>Job state</span><strong class="status-text ${statusClass(job.state)}">${escapeHtml(job.state)}</strong></div>
        <div class="data-cell"><span>Progress</span><strong>${job.completedCount} / ${job.selectedCount}</strong></div>
        <div class="data-cell"><span>Recovery</span><strong>${job.recoveryAttempts} / 1</strong></div>
        <div class="chevron">＋</div>
      </summary>
      <div class="detail-body run-body"></div>
    </details>`);
  const reportCards = reports.map((run) => `
    <details class="run-card" data-run-id="${escapeHtml(run.runId)}">
      <summary>
        <div class="scenario-title"><strong>${escapeHtml(run.runId)}</strong><small>${run.fixture ? "Fixture preview" : "Evidence report"} · ${escapeHtml(run.runMode)}</small></div>
        <div class="data-cell"><span>Execution</span><strong>${run.executionComplete ? "COMPLETE" : "INCOMPLETE"}</strong></div>
        <div class="data-cell"><span>Product verdict</span><strong class="status-text ${statusClass(run.productVerdict)}">${escapeHtml(run.productVerdict)}</strong></div>
        <div class="data-cell"><span>Selected</span><strong>${run.catalog.selected}</strong></div>
        <div class="chevron">＋</div>
      </summary>
      <div class="detail-body run-body"></div>
    </details>`);
  list.innerHTML = [...jobCards, ...reportCards].join("");
  list.querySelectorAll(".run-card").forEach((details) => details.addEventListener("toggle", () => openRun(details, details.dataset.runId)));
}

function runSuiteMatch(item, suite) {
  if (suite === "critical") return /^(tcp|udp)-ipv[46]-(connected-|unconnected-)?(direct|block|proxy)$/.test(item.scenario_id);
  if (suite === "rules") return item.coverage_group === "rule-engine" || item.tags.includes("rule-engine");
  if (suite === "issue206") return item.tags.includes("issue206") || item.scenario_id.startsWith("issue206-");
  if (suite === "issue209") return item.tags.includes("issue209") || item.scenario_id.startsWith("issue209-");
  if (suite === "security") return item.coverage_group === "security" || item.tags.includes("security");
  return true;
}

function getVisibleRunScenarios() {
  const suite = document.querySelector("#run-suite").value;
  const protocol = document.querySelector("#run-filter-protocol").value;
  const family = document.querySelector("#run-filter-family").value;
  const action = document.querySelector("#run-filter-action").value;
  const socket = document.querySelector("#run-filter-socket").value;
  const defect = document.querySelector("#run-filter-defect").value;
  return state.catalog.filter((item) =>
    runSuiteMatch(item, suite) &&
    (!protocol || item.protocol === protocol) &&
    (!family || String(item.family) === family) &&
    (!action || item.action === action) &&
    (!socket || item.socket_mode === socket) &&
    (!defect || (defect === "yes") === Boolean(item.known_defect)));
}

function invalidateRunPreparation() {
  state.runPreparation = null;
  document.querySelector("#run-preparation").hidden = true;
  document.querySelector("#confirm-real-run").checked = false;
  document.querySelector("#start-run").disabled = true;
}

function renderRunBuilder() {
  const mode = document.querySelector("#run-mode").value;
  state.catalog.filter((item) => item.implementation_status !== "EXECUTABLE").forEach((item) => state.runSelection.delete(item.scenario_id));
  state.runVisible = getVisibleRunScenarios();
  const list = document.querySelector("#run-scenario-list");
  list.innerHTML = state.runVisible.map((item) => {
    const blocked = item.implementation_status !== "EXECUTABLE";
    const selected = state.runSelection.has(item.scenario_id);
    return `<label class="run-scenario-choice ${selected ? "selected" : ""} ${blocked ? "blocked" : ""}">
      <input type="checkbox" data-run-scenario="${escapeHtml(item.scenario_id)}" ${selected ? "checked" : ""} ${blocked ? "disabled" : ""}>
      <span><strong>${escapeHtml(item.scenario_id)}</strong><small>${escapeHtml(item.title)} · ${escapeHtml(item.protocol)} IPv${item.family} · ${escapeHtml(item.action)}</small></span>
      <span class="tag">${escapeHtml(item.implementation_status)}</span>
    </label>`;
  }).join("") || '<div class="empty">No scenarios match these run filters.</div>';
  list.querySelectorAll("[data-run-scenario]").forEach((input) => input.addEventListener("change", () => {
    if (input.checked) state.runSelection.add(input.dataset.runScenario);
    else state.runSelection.delete(input.dataset.runScenario);
    invalidateRunPreparation();
    renderRunBuilder();
  }));
  document.querySelector("#run-selected-count").textContent = `${state.runSelection.size} SELECTED`;
  document.querySelector("#run-visible-count").textContent = `${state.runVisible.length} visible`;
  document.querySelector("#review-run").disabled = state.runSelection.size === 0;
}

function renderRunPreparation(preparation) {
  state.runPreparation = preparation;
  document.querySelector("#run-preparation").hidden = false;
  document.querySelector("#run-gates").innerHTML = preparation.gates.map((gate) => `
    <div class="run-gate ${gate.passed ? "ready" : "blocked"}"><strong>${gate.passed ? "✓" : "!"} ${escapeHtml(gate.label)} · ${escapeHtml(gate.status)}</strong><small>${escapeHtml(gate.detail)}${gate.remediation ? `<br>Next: ${escapeHtml(gate.remediation)}` : ""}</small></div>`).join("");
  document.querySelector("#run-warnings").innerHTML = preparation.warnings.map((warning) => `<div class="run-warning">${escapeHtml(warning)}</div>`).join("");
  const real = preparation.mode === "real";
  document.querySelector("#confirm-real-run-label").hidden = !real || !preparation.canStart;
  document.querySelector("#confirm-real-run").checked = false;
  document.querySelector("#start-run").disabled = !preparation.canStart || real;
}

async function reviewRun() {
  const button = document.querySelector("#review-run");
  button.disabled = true;
  try {
    const preparation = await apiJson("/api/v1/runs/dry-run", "POST", {
      mode: document.querySelector("#run-mode").value,
      scenario_ids: [...state.runSelection]
    });
    renderRunPreparation(preparation);
    showToast(preparation.canStart ? "Run review passed. Check the gates, then start." : "Run remains locked. Follow the displayed remediation.");
  } catch (error) { showToast(`Run review failed: ${error.message}`); }
  finally { button.disabled = state.runSelection.size === 0; }
}

function renderLiveJob(job) {
  state.activeJob = job;
  document.querySelector("#live-run-panel").hidden = false;
  document.querySelector("#live-run-title").textContent = job.runId;
  const badge = document.querySelector("#live-run-state");
  badge.textContent = job.state;
  badge.className = `status-badge ${job.state === "COMPLETED" ? "saved" : ["FAILED_TO_START", "SAFETY_STOPPED"].includes(job.state) ? "warning" : "neutral"}`;
  document.querySelector("#live-current-scenario").textContent = job.currentScenarioId || (job.terminal ? "No active scenario" : "Waiting for runner");
  document.querySelector("#live-current-phase").textContent = job.currentPhase;
  document.querySelector("#live-progress-text").textContent = `${job.completedCount} / ${job.selectedCount}`;
  document.querySelector("#live-recovery-count").textContent = `${job.recoveryAttempts} / 1`;
  document.querySelector("#live-progress-bar").style.width = `${job.selectedCount ? Math.min(100, (job.completedCount / job.selectedCount) * 100) : 0}%`;
  document.querySelector("#live-terminal-reason").textContent = job.terminalReason || "Product outcomes continue to later independent tests while cleanup and shared-state health remain proven clean.";
  const completed = new Map(job.scenarios.map((item) => [item.scenarioId, item]));
  document.querySelector("#live-scenarios").innerHTML = job.scenarioIds.map((scenarioId) => {
    const item = completed.get(scenarioId);
    const status = item?.status || (job.currentScenarioId === scenarioId ? "RUNNING" : "PENDING");
    return `<div class="live-scenario"><div><strong>${escapeHtml(scenarioId)}</strong><small>${escapeHtml(item?.detail || (status === "RUNNING" ? "Runner contract in progress." : "Waiting in the selected sequence."))}</small></div><span class="status-text ${statusClass(status)}">${escapeHtml(status)}</span></div>`;
  }).join("");
  document.querySelector("#live-transitions").innerHTML = job.transitions.slice().reverse().slice(0, 10).map((transition) => `
    <div class="live-transition"><div><strong>${escapeHtml(transition.state)}</strong><small>${escapeHtml(transition.detail)}</small></div><small>${new Date(transition.timestampUtc).toLocaleTimeString()}</small></div>`).join("");
  document.querySelector("#cancel-run").disabled = job.terminal || job.cancellationRequested;
  document.querySelector("#open-run-results").hidden = !job.terminal;
}

async function refreshRunLists() {
  const runs = await getJson("/api/v1/runs");
  state.jobs = runs.jobs;
  state.reports = runs.reports;
  renderRuns();
}

async function pollActiveRun() {
  if (!state.activeJob) return;
  try {
    const data = await getJson(`/api/v1/runs/${encodeURIComponent(state.activeJob.runId)}`);
    renderLiveJob(data.job);
    if (data.job.terminal) {
      window.clearInterval(state.runPollTimer);
      state.runPollTimer = null;
      await refreshRunLists();
      showToast(`Run finished with controller state ${data.job.state}.`);
    }
  } catch (error) { showToast(`Live run update failed: ${error.message}`); }
}

async function startRun() {
  if (!state.runPreparation?.canStart) return;
  const button = document.querySelector("#start-run");
  button.disabled = true;
  try {
    const job = await apiJson("/api/v1/runs", "POST", {
      mode: state.runPreparation.mode,
      scenario_ids: state.runPreparation.scenarioIds,
      confirmation_nonce: state.runPreparation.confirmationNonce
    });
    renderLiveJob(job);
    document.querySelector("#live-run-panel").scrollIntoView({ behavior: "smooth", block: "start" });
    if (state.runPollTimer) window.clearInterval(state.runPollTimer);
    state.runPollTimer = window.setInterval(pollActiveRun, 750);
    await refreshRunLists();
  } catch (error) { showToast(`Run could not start: ${error.message}`); button.disabled = false; }
}

async function cancelActiveRun() {
  if (!state.activeJob || state.activeJob.terminal) return;
  try {
    const job = await apiJson(`/api/v1/runs/${encodeURIComponent(state.activeJob.runId)}/cancel`, "POST");
    renderLiveJob(job);
    showToast("Cancellation requested. The current bounded operation will clean up before the job stops.");
  } catch (error) { showToast(`Cancellation failed: ${error.message}`); }
}

function getPublicSetting(field) {
  return state.settingsView?.settings?.[field.section]?.[field.name];
}

function fieldInput(field) {
  const id = `setting-${field.id.replaceAll(".", "-")}`;
  if (field.sensitive) {
    const present = state.settingsView.protectedPresence[field.id] === true;
    return `
      <div class="protected-input">
        <input id="${id}" data-field-id="${escapeHtml(field.id)}" data-sensitive="true" type="text" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="${present ? "Saved — enter a new value to replace" : "Not configured"}">
        <span class="presence ${present ? "saved" : "missing"}">${present ? "SAVED" : "MISSING"}</span>
      </div>
      ${present && !field.id.startsWith("local_product.") && field.id !== "retention.evidence_root" ? `<label class="clear-value"><input type="checkbox" data-clear-field="${escapeHtml(field.id)}"> Forget stored value</label>` : ""}`;
  }

  const value = getPublicSetting(field);
  if (field.type === "boolean") {
    return `<label class="switch"><input id="${id}" data-field-id="${escapeHtml(field.id)}" type="checkbox" ${value ? "checked" : ""}><span></span><strong>${value ? "Enabled" : "Disabled"}</strong></label>`;
  }
  if (field.type === "choice") {
    return `<select id="${id}" data-field-id="${escapeHtml(field.id)}"><option value="dark" ${value === "dark" ? "selected" : ""}>Dark</option></select>`;
  }
  const numberType = ["number", "port", "milliseconds"].includes(field.type);
  return `<input id="${id}" data-field-id="${escapeHtml(field.id)}" type="${numberType ? "number" : "text"}" value="${escapeHtml(value ?? "")}" ${field.minimum !== null && field.minimum !== undefined ? `min="${field.minimum}"` : ""} ${field.maximum !== null && field.maximum !== undefined ? `max="${field.maximum}"` : ""} autocomplete="off">`;
}

function renderSettingsNavigation() {
  const container = document.querySelector("#settings-section-list");
  const primary = state.settingsSchema.sections.filter((section) => !advancedSettingsSections.has(section.id));
  const advanced = state.settingsSchema.sections.filter((section) => advancedSettingsSections.has(section.id));
  const buttonFor = (section) => {
    const index = state.settingsSchema.sections.findIndex((item) => item.id === section.id);
    return `
    <button type="button" class="settings-section ${section.id === state.settingsSection ? "active" : ""}" data-settings-section="${escapeHtml(section.id)}">
      <span>${String(index + 1).padStart(2, "0")}</span>${escapeHtml(section.title)}
    </button>`;
  };
  const advancedOpen = advanced.some((section) => section.id === state.settingsSection);
  container.innerHTML = primary.map(buttonFor).join("") + `
    <details class="settings-advanced-navigation" ${advancedOpen ? "open" : ""}>
      <summary>Advanced settings</summary>
      <div>${advanced.map(buttonFor).join("")}</div>
    </details>`;
  container.querySelectorAll("[data-settings-section]").forEach((button) => button.addEventListener("click", () => {
    state.settingsSection = button.dataset.settingsSection;
    renderSettingsNavigation();
    renderSettingsFields();
  }));
}

function settingFieldMarkup(field) {
  return `
    <div class="setting-field" data-setting-field="${escapeHtml(field.id)}">
      <div class="field-heading"><label for="setting-${escapeHtml(field.id.replaceAll(".", "-"))}">${escapeHtml(field.label)}</label>${field.required ? '<span>REQUIRED</span>' : '<span class="optional">OPTIONAL</span>'}</div>
      ${fieldInput(field)}
      <small>${escapeHtml(field.description)}</small>
    </div>`;
}

function renderValidation(validation) {
  const panel = document.querySelector("#settings-validation");
  const issues = [...validation.invalidFields, ...validation.readinessIssues];
  panel.hidden = issues.length === 0;
  panel.className = `validation-summary ${validation.validForSave ? "incomplete" : "invalid"}`;
  panel.innerHTML = issues.length ? `<strong>${validation.validForSave ? "Configuration saved, but not ready" : "Correct invalid values before saving"}</strong><ul>${issues.slice(0, 8).map((issue) => `<li data-issue-field="${escapeHtml(issue.field)}">${escapeHtml(issue.message)}</li>`).join("")}</ul>${issues.length > 8 ? `<small>${issues.length - 8} additional readiness requirements are not shown in this section.</small>` : ""}` : "";

  document.querySelector("#settings-ready-dot").className = validation.ready ? "ready" : "pending";
  document.querySelector("#settings-ready-label").textContent = validation.ready ? "Configuration ready" : "Configuration incomplete";
  document.querySelector("#settings-ready-detail").textContent = validation.ready ? "All local settings are valid" : `${validation.invalidFields.length + validation.readinessIssues.length} item(s) require attention`;
}

function renderSettingsFields() {
  const section = state.settingsSchema.sections.find((item) => item.id === state.settingsSection);
  const fields = state.settingsSchema.fields.filter((field) => field.section === state.settingsSection);
  document.querySelector("#settings-section-title").textContent = section.title;
  document.querySelector("#settings-section-description").textContent = section.description;
  const guidance = {
    local_product: '<div class="automatic-note"><strong>Automatic local artifacts</strong><br>The traffic client is loaded from the TestLab bin folder. Standard ProxyBridge paths are preconfigured and all binary integrity values are calculated internally.</div>',
    proxy: '<div class="automatic-note"><strong>Why a SOCKS5 proxy is needed</strong><br>Only PROXY scenarios use this endpoint. ProxyBridge connects to it so TestLab can prove that traffic took the proxy path instead of DIRECT or BLOCK. TestLab does not expose credentials here; the generated profile references the existing endpoint by ID.</div>',
    server_connection: '<div class="automatic-note"><strong>Only three values normally matter</strong><br>Enter the server address, SSH user and private key. Port 22 is already selected unless your SSH service uses a custom port.</div>',
    server_endpoint: '<div class="automatic-note"><strong>Listeners and evidence are automatic</strong><br>TestLab provisions the TCP/UDP listeners and manages the server evidence path. Normally you only confirm this Windows PC address and the Linux server address.</div>',
    capabilities: '<div class="automatic-note"><strong>Capabilities control selection</strong><br>Disabling an unavailable family skips its scenarios explicitly. A skipped test is never reported as passed.</div>'
  }[state.settingsSection] ?? "";
  const useNestedAdvanced = !advancedSettingsSections.has(state.settingsSection);
  const primaryFields = useNestedAdvanced ? fields.filter((field) => !advancedSettingFields.has(field.id)) : fields;
  const advancedFields = useNestedAdvanced ? fields.filter((field) => advancedSettingFields.has(field.id)) : [];
  const advancedMarkup = advancedFields.length ? `
    <details class="settings-advanced-fields">
      <summary>Show advanced options <span>Defaults are recommended</span></summary>
      <div class="settings-advanced-grid">${advancedFields.map(settingFieldMarkup).join("")}</div>
    </details>` : "";
  document.querySelector("#settings-fields").innerHTML = guidance + primaryFields.map(settingFieldMarkup).join("") + advancedMarkup;
  document.querySelectorAll(".switch input").forEach((input) => input.addEventListener("change", () => { input.closest(".switch").querySelector("strong").textContent = input.checked ? "Enabled" : "Disabled"; }));
  renderValidation(state.settingsView.validation);
}

function buildSettingsRequest() {
  const settings = structuredClone(state.settingsView.settings);
  const protectedValues = {};
  const clearProtected = [];
  state.settingsSchema.fields.forEach((field) => {
    const input = document.querySelector(`[data-field-id="${field.id}"]`);
    if (!input) return;
    if (field.sensitive) {
      if (input.value !== "") protectedValues[field.id] = input.value;
      const clear = document.querySelector(`[data-clear-field="${field.id}"]`);
      if (clear?.checked) clearProtected.push(field.id);
      return;
    }
    if (field.type === "boolean") settings[field.section][field.name] = input.checked;
    else if (["number", "port", "milliseconds"].includes(field.type)) settings[field.section][field.name] = Number(input.value);
    else settings[field.section][field.name] = input.value;
  });
  return { settings, protected_values: protectedValues, clear_protected: clearProtected };
}

async function sendSettings(method) {
  const response = await fetch(method === "PUT" ? "/api/v1/settings" : "/api/v1/settings/validate", {
    method,
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-TestLab-CSRF": state.csrfToken },
    body: JSON.stringify(buildSettingsRequest())
  });
  const body = await response.json();
  if (!response.ok) {
    if (body.validation) renderValidation(body.validation);
    throw new Error(body.error || `${response.status} ${response.statusText}`);
  }
  return body;
}

async function validateSettings() {
  const button = document.querySelector("#validate-settings");
  if (!beginButtonAction(button, "Validating...")) return;
  try {
    const validation = await sendSettings("POST");
    renderValidation(validation);
    showToast(validation.ready ? "Configuration is ready." : "Validation complete. Incomplete values may still be saved.");
  } catch (error) { showToast(`Validation failed: ${error.message}`); }
  finally { endButtonAction(button); }
}

async function saveSettings(event) {
  event.preventDefault();
  const button = event.submitter;
  if (!beginButtonAction(button, "Saving...")) return;
  try {
    state.settingsView = await sendSettings("PUT");
    document.querySelector("#settings-save-state").textContent = "SAVED";
    document.querySelector("#settings-save-state").className = "status-badge saved";
    renderSettingsFields();
    state.serverStatus = await getJson("/api/v1/server/status");
    renderServerStatus(state.serverStatus);
    showToast(state.settingsView.validation.ready ? "Settings saved. Configuration is ready." : "Settings saved. Readiness requirements remain.");
  } catch (error) { showToast(`Settings were not saved: ${error.message}`); }
  finally { endButtonAction(button); }
}

async function apiJson(url, method, body) {
  const headers = { Accept: "application/json", "X-TestLab-CSRF": state.csrfToken };
  const options = { method, headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(body);
  }
  const response = await fetch(url, options);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `${response.status} ${response.statusText}`);
  return result;
}

function renderServerStatus(status) {
  state.serverStatus = status;
  const ready = status.state === "READY";
  const badge = document.querySelector("#server-state");
  badge.textContent = status.state;
  badge.className = `status-badge ${ready ? "saved" : status.state === "ERROR" || status.state === "UNSUPPORTED" ? "warning" : "neutral"}`;
  document.querySelector("#server-message").textContent = status.message;
  document.querySelector("#server-remediation").innerHTML = (status.remediation || []).map((item) => `<li>${escapeHtml(item)}</li>`).join("");
  document.querySelector("#refresh-metrics").disabled = !ready;
  document.querySelector("#protocol-smoke").disabled = !ready;

  document.querySelector("#dashboard-server-title").textContent = ready ? "Test server is ready" : "Test server requires setup";
  document.querySelector("#dashboard-server-message").textContent = status.message;
  document.querySelector("#dashboard-server-state").textContent = status.state;
  document.querySelector("#dashboard-server-state").className = ready ? "" : "muted";
  const localReady = state.settingsView?.validation?.ready === true;
  document.querySelector("#gate-local").className = localReady ? "ready" : "pending";
  document.querySelector("#gate-local").querySelector("small").textContent = localReady ? "Saved configuration passed local validation" : "Complete Environment Setup";
  document.querySelector("#gate-server").className = ready ? "ready" : "pending";
  document.querySelector("#gate-server").querySelector("small").textContent = ready ? "Provisioning receipt is current in this controller session" : "Debian or Ubuntu with systemd must be provisioned";
  const runtimeReady = state.realRuntimeAvailable && localReady && ready;
  document.querySelector("#gate-runtime").className = runtimeReady ? "ready" : "locked";
  document.querySelector("#gate-runtime").querySelector("small").textContent = runtimeReady ? "Available only after a fresh per-run review and one-time confirmation" : "Locked until local and server readiness pass";
  document.querySelector("#dashboard-runtime-state").textContent = runtimeReady ? "GUARDED READY" : "LOCKED";
  document.querySelector("#dashboard-runtime-state").className = runtimeReady ? "" : "muted";
}

function discoveryItem(label, value) {
  return `<div class="discovery-item"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`;
}

function renderServerValidation(result) {
  state.serverValidation = result;
  renderServerStatus({
    state: result.state,
    message: result.message,
    remediation: result.remediation || [],
    configurationComplete: result.state !== "UNCONFIGURED",
    hostTrusted: result.state !== "NEEDS_HOST_TRUST",
    receiptCurrent: result.state === "READY"
  });

  const trustPanel = document.querySelector("#host-trust-panel");
  trustPanel.hidden = result.state !== "NEEDS_HOST_TRUST";
  if (!trustPanel.hidden) {
    document.querySelector("#host-trust-message").textContent = result.message;
    document.querySelector("#host-fingerprints").innerHTML = result.fingerprints.map((value) => `<code>${escapeHtml(value)}</code>`).join("");
    document.querySelector("#replace-host-key-label").hidden = !result.hostKeyChanged;
    document.querySelector("#replace-host-key").checked = false;
    document.querySelector("#trust-host").disabled = result.hostKeyChanged;
  }

  const discoveryPanel = document.querySelector("#server-discovery-panel");
  discoveryPanel.hidden = !result.discovery;
  if (result.discovery) {
    const item = result.discovery;
    document.querySelector("#server-discovery").innerHTML = [
      discoveryItem("Operating system", `${item.operatingSystem} ${item.version}`),
      discoveryItem("Architecture", item.architecture),
      discoveryItem("systemd PID 1", item.systemd ? "VERIFIED" : "MISSING"),
      discoveryItem("sudo -n", item.nonInteractiveSudo ? "VERIFIED" : "UNAVAILABLE"),
      discoveryItem("Python 3", item.python3 ? "INSTALLED" : "WILL INSTALL"),
      discoveryItem("Available disk", `${Math.floor(item.availableDiskKb / 1024)} MiB`),
      discoveryItem("Endpoint service", item.serviceState),
      discoveryItem("Firewall ownership", item.firewallAdapter)
    ].join("");
    document.querySelector("#create-server-plan").disabled = !["PLAN_READY", "REPAIR_REQUIRED", "READY"].includes(result.state);
  }
}

async function validateServer(request = {}) {
  const button = document.querySelector("#validate-server");
  if (!beginButtonAction(button, "Validating...")) return;
  try {
    const result = await apiJson("/api/v1/server/validate", "POST", request);
    renderServerValidation(result);
    showToast(result.message);
  } catch (error) { showToast(`Server validation failed: ${error.message}`); }
  finally { endButtonAction(button); }
}

async function trustServerHost() {
  const validation = state.serverValidation;
  if (!validation?.trustToken) return;
  const replace = document.querySelector("#replace-host-key").checked;
  if (validation.hostKeyChanged && !replace) {
    showToast("Confirm the independently verified server fingerprint first.");
    return;
  }
  const button = document.querySelector("#trust-host");
  if (!beginButtonAction(button, "Trusting host...")) return;
  try {
    await validateServer({ trust_token: validation.trustToken, confirm_host_trust: true, replace_changed_host_key: replace });
  }
  finally {
    const stillNeedsTrust = state.serverValidation?.state === "NEEDS_HOST_TRUST";
    endButtonAction(button, stillNeedsTrust && state.serverValidation?.hostKeyChanged && !document.querySelector("#replace-host-key").checked);
  }
}

function renderServerPlan(plan) {
  state.serverPlan = plan;
  const expiry = new Date(plan.expiresUtc);
  document.querySelector("#server-plan-panel").hidden = false;
  document.querySelector("#server-plan-expiry").textContent = `EXPIRES ${expiry.toLocaleTimeString()}`;
  document.querySelector("#server-plan-summary").innerHTML = `
    <div class="plan-meta">
      <span class="tag">${escapeHtml(plan.state)}</span>
      <span class="tag">${plan.packages.length ? `${plan.packages.length} package(s)` : "No package changes"}</span>
      <span class="tag">${plan.paths.length} managed paths</span>
      <span class="tag">TCP/UDP ${plan.tcpPorts.map(escapeHtml).join(", ")}</span>
      <span class="tag">${Object.keys(plan.artifactSha256).length} integrity-checked artifacts</span>
    </div>
    <details class="scenario"><summary><div class="scenario-title"><strong>Remote command</strong><small>Fixed by TestLab; the browser cannot supply command text</small></div><div class="chevron">＋</div></summary><div class="detail-body"><pre>${escapeHtml(plan.commands.join("\n"))}</pre></div></details>
    ${plan.warnings.map((warning) => `<div class="validation-summary incomplete"><strong>Boundary</strong><ul><li>${escapeHtml(warning)}</li></ul></div>`).join("")}`;
  document.querySelector("#server-plan-steps").innerHTML = plan.steps.map((step) => `
    <div class="plan-step"><span>${String(step.order).padStart(2, "0")}</span><div><strong>${escapeHtml(step.operation)}</strong><small>${escapeHtml(step.description)}<br>Rollback: ${escapeHtml(step.rollback)}</small></div></div>`).join("");
  document.querySelector("#confirm-server-plan").checked = false;
  const button = document.querySelector("#apply-server-plan");
  button.disabled = true;
  button.textContent = plan.state === "REPAIR_REQUIRED" ? "Apply repair plan" : plan.state === "NO_CHANGE_VERIFY" ? "Verify without changes" : "Apply plan";
}

async function createServerPlan() {
  const button = document.querySelector("#create-server-plan");
  if (!beginButtonAction(button, "Creating plan...")) return;
  try {
    renderServerPlan(await apiJson("/api/v1/server/plan", "POST"));
    showToast("Exact server plan created. Review it before confirmation.");
  } catch (error) { showToast(`Plan could not be created: ${error.message}`); }
  finally { endButtonAction(button); }
}

async function applyServerPlan() {
  if (!state.serverPlan || !document.querySelector("#confirm-server-plan").checked) return;
  const button = document.querySelector("#apply-server-plan");
  if (!beginButtonAction(button, "Applying and verifying...")) return;
  const endpoint = state.serverPlan.state === "REPAIR_REQUIRED" ? "/api/v1/server/repair" : "/api/v1/server/apply";
  try {
    const result = await apiJson(endpoint, "POST", { plan_id: state.serverPlan.planId, confirmed: true });
    showToast(result.message);
    document.querySelector("#server-plan-panel").hidden = result.state === "READY";
    renderServerStatus(await getJson("/api/v1/server/status"));
  } catch (error) { showToast(`Server changes were not completed: ${error.message}`); }
  finally { endButtonAction(button, !document.querySelector("#confirm-server-plan").checked); }
}

async function refreshServerMetrics() {
  const button = document.querySelector("#refresh-metrics");
  if (!beginButtonAction(button, "Refreshing...")) return;
  try {
    const metrics = await getJson("/api/v1/server/metrics");
    document.querySelector("#server-metrics-panel").hidden = false;
    document.querySelector("#server-metrics").innerHTML = [
      discoveryItem("Service", `${metrics.serviceState} / ${metrics.serviceSubstate}`),
      discoveryItem("Main PID", metrics.mainPid),
      discoveryItem("Restarts", metrics.restartCount),
      discoveryItem("Memory", `${Math.floor(metrics.memoryBytes / 1024 / 1024)} MiB`),
      discoveryItem("Evidence records", metrics.evidenceRecords),
      discoveryItem("Endpoint errors", metrics.endpointErrors),
      discoveryItem("Evidence size", `${metrics.evidenceBytes} bytes`),
      discoveryItem("Available disk", `${Math.floor(metrics.availableDiskKb / 1024)} MiB`)
    ].join("");
    document.querySelector("#server-log-messages").innerHTML = metrics.recentSanitizedMessages.length
      ? metrics.recentSanitizedMessages.map((message) => `<code>${escapeHtml(message)}</code>`).join("")
      : '<div class="empty">No recent warning or error messages.</div>';
    showToast("Sanitized server metrics refreshed.");
  } catch (error) { showToast(`Metrics unavailable: ${error.message}`); }
  finally { endButtonAction(button, state.serverStatus?.state !== "READY"); }
}

async function runProtocolSmoke() {
  const button = document.querySelector("#protocol-smoke");
  if (!beginButtonAction(button, "Testing protocols...")) return;
  try {
    const result = await apiJson("/api/v1/server/protocol-smoke", "POST");
    document.querySelector("#protocol-smoke-panel").hidden = false;
    const badge = document.querySelector("#protocol-smoke-state");
    badge.textContent = result.state;
    badge.className = `status-badge ${result.state === "PASS" ? "saved" : "warning"}`;
    document.querySelector("#protocol-smoke-message").textContent = result.message;
    document.querySelector("#protocol-smoke-results").innerHTML = result.results.length
      ? result.results.map((item) => discoveryItem(item.scenarioId, `${item.status} · client ${item.clientRecords} / server ${item.serverRecords}`)).join("")
      : discoveryItem("Result", result.state);
    showToast(result.message);
  } catch (error) { showToast(`Protocol smoke unavailable: ${error.message}`); }
  finally { endButtonAction(button, state.serverStatus?.state !== "READY"); }
}

async function initialize() {
  document.querySelectorAll(".nav-item[data-view]").forEach((button) => button.addEventListener("click", () => switchView(button.dataset.view)));
  ["catalog-search", "filter-protocol", "filter-family", "filter-action", "filter-status"].forEach((id) => document.querySelector(`#${id}`).addEventListener("input", renderCatalog));

  try {
    const [system, catalog, runs, settingsSchema, settingsView] = await Promise.all([
      getJson("/api/v1/system/status"),
      getJson("/api/v1/catalog"),
      getJson("/api/v1/runs"),
      getJson("/api/v1/settings/schema"),
      getJson("/api/v1/settings")
    ]);
    state.catalog = catalog.items;
    state.jobs = runs.jobs;
    state.reports = runs.reports;
    state.settingsSchema = settingsSchema;
    state.settingsView = settingsView;
    state.csrfToken = system.csrf_token;
    state.serverStatus = system.server;
    state.realRuntimeAvailable = system.real_runtime_available;
    document.querySelector("#metric-declared").textContent = system.catalog.declared;
    document.querySelector("#metric-executable").textContent = system.catalog.executable;
    document.querySelector("#metric-declarative").textContent = system.catalog.declarative;
    document.querySelector("#metric-reports").textContent = system.available_reports;
    renderCatalog();
    renderRuns();
    ["tcp-ipv4-direct", "tcp-ipv4-block", "tcp-ipv4-proxy"].filter((id) => state.catalog.some((item) => item.scenario_id === id)).forEach((id) => state.runSelection.add(id));
    renderRunBuilder();
    renderSettingsNavigation();
    renderSettingsFields();
    renderServerStatus(state.serverStatus);
  } catch (error) {
    showToast(`Read-only data could not be loaded: ${error.message}`);
    document.querySelector("#catalog-list").innerHTML = '<div class="error">Catalog unavailable.</div>';
    document.querySelector("#runs-list").innerHTML = '<div class="error">Reports unavailable.</div>';
  }

  const requestedView = window.location.hash.slice(1);
  if (["dashboard", "catalog", "run", "results", "settings", "server"].includes(requestedView)) switchView(requestedView);
}

document.querySelector("#settings-form").addEventListener("submit", saveSettings);
document.querySelector("#validate-settings").addEventListener("click", validateSettings);
document.querySelectorAll("[data-open-server]").forEach((button) => button.addEventListener("click", () => switchView("server")));
document.querySelector("#validate-server").addEventListener("click", () => validateServer());
document.querySelector("#replace-host-key").addEventListener("change", (event) => { document.querySelector("#trust-host").disabled = state.serverValidation?.hostKeyChanged && !event.target.checked; });
document.querySelector("#trust-host").addEventListener("click", trustServerHost);
document.querySelector("#create-server-plan").addEventListener("click", createServerPlan);
document.querySelector("#confirm-server-plan").addEventListener("change", (event) => { document.querySelector("#apply-server-plan").disabled = !event.target.checked; });
document.querySelector("#apply-server-plan").addEventListener("click", applyServerPlan);
document.querySelector("#refresh-metrics").addEventListener("click", refreshServerMetrics);
document.querySelector("#protocol-smoke").addEventListener("click", runProtocolSmoke);
document.querySelectorAll("[data-open-run]").forEach((button) => button.addEventListener("click", () => switchView("run")));
["run-mode", "run-suite", "run-filter-protocol", "run-filter-family", "run-filter-action", "run-filter-socket", "run-filter-defect"].forEach((id) => document.querySelector(`#${id}`).addEventListener("change", () => { invalidateRunPreparation(); renderRunBuilder(); }));
document.querySelector("#select-visible-tests").addEventListener("click", () => {
  const mode = document.querySelector("#run-mode").value;
    state.runVisible.filter((item) => item.implementation_status === "EXECUTABLE").forEach((item) => state.runSelection.add(item.scenario_id));
  invalidateRunPreparation(); renderRunBuilder();
});
document.querySelector("#clear-selected-tests").addEventListener("click", () => { state.runSelection.clear(); invalidateRunPreparation(); renderRunBuilder(); });
document.querySelector("#review-run").addEventListener("click", reviewRun);
document.querySelector("#confirm-real-run").addEventListener("change", (event) => { document.querySelector("#start-run").disabled = !state.runPreparation?.canStart || !event.target.checked; });
document.querySelector("#start-run").addEventListener("click", startRun);
document.querySelector("#cancel-run").addEventListener("click", cancelActiveRun);
document.querySelector("#open-run-results").addEventListener("click", () => switchView("results"));
initialize();
