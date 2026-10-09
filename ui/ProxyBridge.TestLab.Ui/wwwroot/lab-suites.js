// Templates store choices independently from build identity and one-use launch plans.
Object.assign(labText.ru, {
  savedSuites: "Сохранённые наборы", savedSuitesHelp: "Сохраните тесты и их параметры, чтобы повторить набор с другой сборкой. Перед каждым запуском подготовьте новый план; сохранённый набор не подтверждает готовность.",
  chooseSuite: "Выберите набор", suiteName: "Название набора", applySuite: "Выбрать набор", saveNewSuite: "Сохранить новый", updateSuite: "Обновить выбранный", deleteSuite: "Удалить набор",
  suiteSaved: "Набор сохранён.", suiteApplied: "Набор выбран. Подготовьте новый запуск для выбранной сборки.", suiteDeleted: "Набор удалён. Текущий выбор тестов сохранён.",
  SUITE_CATALOG_UNAVAILABLE: "Не удалось прочитать сохранённые наборы. Обновите страницу; сохранение отключено до успешного чтения.",
  SUITE_NAME_INVALID: "Введите название набора: от 1 до 64 символов без управляющих знаков.", SUITE_NAME_EXISTS: "Такое название уже есть. Укажите другое или обновите выбранный набор.",
  SUITE_CATALOG_LIMIT_REACHED: "Сохранено слишком много наборов. Удалите ненужный набор.", SUITE_NOT_FOUND: "Набор больше не существует. Обновите страницу.",
  SUITE_SAVE_FAILED: "Сохранение не подтверждено. Обновите страницу перед повторной попыткой.", SUITE_DELETE_FAILED: "Удаление не подтверждено. Обновите страницу перед повторной попыткой."
});
Object.assign(labText.en, {
  savedSuites: "Saved suites", savedSuitesHelp: "Save tests and their settings to repeat a suite with another build. Prepare a fresh plan before every run; a saved suite does not establish readiness.",
  chooseSuite: "Choose a suite", suiteName: "Suite name", applySuite: "Use suite", saveNewSuite: "Save new", updateSuite: "Update selected", deleteSuite: "Delete suite",
  suiteSaved: "Suite saved.", suiteApplied: "Suite selected. Prepare a fresh launch for the selected build.", suiteDeleted: "Suite deleted. Current test choices are retained.",
  SUITE_CATALOG_UNAVAILABLE: "Saved suites could not be read. Refresh the page; saving is disabled until a successful read.",
  SUITE_NAME_INVALID: "Enter a suite name: 1 to 64 characters without control characters.", SUITE_NAME_EXISTS: "That name already exists. Choose another name or update the selected suite.",
  SUITE_CATALOG_LIMIT_REACHED: "Too many saved suites. Delete an unused suite.", SUITE_NOT_FOUND: "The suite no longer exists. Refresh the page.",
  SUITE_SAVE_FAILED: "Saving is not confirmed. Refresh the page before retrying.", SUITE_DELETE_FAILED: "Deletion is not confirmed. Refresh the page before retrying."
});
const suiteCatalog = { items: [], available: false, message: null };
let savedSuiteOptionsKey = "";

function renderSavedSuites(busy) {
  const selected = lab("lab-saved-suite").value;
  const optionsKey = JSON.stringify([suiteCatalog.items, labLanguage]);
  if (optionsKey !== savedSuiteOptionsKey) {
    savedSuiteOptionsKey = optionsKey;
    lab("lab-saved-suite").innerHTML = `<option value="">${html(t("chooseSuite"))}</option>` + suiteCatalog.items.map(item =>
      `<option value="${html(item.id)}">${html(item.name)}</option>`).join("");
  }
  if (suiteCatalog.items.some(item => item.id === selected)) lab("lab-saved-suite").value = selected;
  const hasSelection = !!lab("lab-saved-suite").value;
  lab("lab-saved-suite").disabled = busy || !suiteCatalog.available;
  lab("lab-suite-name").disabled = busy;
  lab("lab-suite-apply").disabled = busy || !hasSelection || !suiteCatalog.available;
  lab("lab-suite-save").disabled = busy || !labState.csrf || !suiteCatalog.available || !(lab("lab-mode").value === "remote" ? trafficCases() : selectedTests()).length;
  lab("lab-suite-update").disabled = lab("lab-suite-save").disabled || !hasSelection;
  lab("lab-suite-delete").disabled = busy || !labState.csrf || !suiteCatalog.available || !hasSelection;
  lab("lab-suite-status").textContent = suiteCatalog.message ? t(suiteCatalog.message) : "";
}

async function loadSavedSuites() {
  try {
    const response = await fetch("/api/v1/lab/suites", { cache: "no-store", signal: AbortSignal.timeout(10000) });
    const data = await response.json();
    if (!response.ok || !Array.isArray(data.items)) throw new Error("catalog");
    suiteCatalog.items = data.items;
    suiteCatalog.available = true;
    if (suiteCatalog.message === "SUITE_CATALOG_UNAVAILABLE") suiteCatalog.message = null;
  } catch {
    suiteCatalog.available = false;
    suiteCatalog.items = [];
    suiteCatalog.message = "SUITE_CATALOG_UNAVAILABLE";
  }
}

function applySavedSuite() {
  if (labActionActive || runActive() || trafficState?.execution?.active || !suiteCatalog.available) return;
  const entry = suiteCatalog.items.find(item => item.id === lab("lab-saved-suite").value);
  if (!entry) return;
  lab("lab-mode").value = entry.mode;
  if (entry.mode === "remote") {
    const legacy = {tcp_rtt:["tcp-rtt"],tcp_transfer:["tcp-upload","tcp-download"],tcp_rtt_three_modes:["three-modes"],tcp_connections:["tcp-connections"]};
    trafficChoice = {};
    for (const test of entry.tests) for (const id of legacy[test.scenario] || [test.scenario])
      trafficChoice[id] = {selected:true,duration:test.duration,load:test.load};
    localStorage.setItem("testlab-traffic-choice",JSON.stringify(trafficChoice));
  } else {
  setSelectedTests(entry.tests.map(test => test.scenario));
  for (const test of entry.tests) {
    document.querySelector(`[data-test-duration="${test.scenario}"]`).value = test.duration;
    document.querySelector(`[data-test-load="${test.scenario}"]`).value = test.load;
  }
  }
  lab("lab-suite-name").value = entry.name;
  labState.plan = null;
  labState.planFailed = false;
  suiteCatalog.message = "suiteApplied";
  saveTestingChoice();
  renderLab();
}

async function changeSavedSuite(action) {
  if (labActionActive || runActive() || trafficState?.execution?.active || !labState.csrf || !suiteCatalog.available) return;
  const id = action === "save" ? null : lab("lab-saved-suite").value;
  if (action !== "save" && !id) return;
  labActionActive = true;
  suiteCatalog.message = null;
  renderLab();
  try {
    const response = await fetch(`/api/v1/lab/suites/${action === "delete" ? "delete" : "save"}`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf },
      signal: AbortSignal.timeout(10000),
      body: JSON.stringify(action === "delete" ? { id } : { id, name: lab("lab-suite-name").value, mode: lab("lab-mode").value,
        tests: lab("lab-mode").value === "remote" ? trafficCases().map(row=>({scenario:row.id,duration:row.duration,load:row.load})) : selectedWorkloads() })
    });
    const result = await response.json();
    if (!response.ok) { suiteCatalog.message = result.error || "SUITE_SAVE_FAILED"; }
    else {
      await loadSavedSuites();
      if (suiteCatalog.available) {
        renderSavedSuites(true);
        lab("lab-saved-suite").value = action === "delete" ? "" : result.id;
        suiteCatalog.message = action === "delete" ? "suiteDeleted" : "suiteSaved";
      }
    }
  } catch { suiteCatalog.message = action === "delete" ? "SUITE_DELETE_FAILED" : "SUITE_SAVE_FAILED"; }
  finally { labActionActive = false; renderLab(); scheduleRunPoll(); }
}

lab("lab-saved-suite").addEventListener("change", () => {
  const entry = suiteCatalog.items.find(item => item.id === lab("lab-saved-suite").value);
  lab("lab-suite-name").value = entry?.name || "";
  suiteCatalog.message = null;
  renderLab();
});
lab("lab-suite-apply").addEventListener("click", applySavedSuite);
lab("lab-suite-save").addEventListener("click", () => changeSavedSuite("save"));
lab("lab-suite-update").addEventListener("click", () => changeSavedSuite("update"));
lab("lab-suite-delete").addEventListener("click", () => changeSavedSuite("delete"));

restoreTestingChoice();
setupResults();
navigateLab(labPage, false, false);
renderLab();
loadLab();
