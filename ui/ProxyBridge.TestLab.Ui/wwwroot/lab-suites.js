// Templates store choices independently from build identity and one-use launch plans.
Object.assign(labText.ru, {
  savedSuites: "Сохранённые наборы", savedSuitesHelp: "Сохраните тесты и их параметры, чтобы повторить набор с другой сборкой. Перед каждым запуском заново проверяются сборка и среда; сохранённый набор не подтверждает готовность.",
  chooseSuite: "Выберите набор", suiteName: "Название набора", applySuite: "Выбрать набор", saveNewSuite: "Сохранить новый", updateSuite: "Обновить выбранный", deleteSuite: "Удалить набор",
  suiteSaved: "Набор сохранён.", suiteApplied: "Набор выбран. Подготовьте новый запуск для выбранной сборки.", suiteDeleted: "Набор удалён. Текущий выбор тестов сохранён.",
  SUITE_CATALOG_UNAVAILABLE: "Не удалось прочитать сохранённые наборы. Обновите страницу; сохранение отключено до успешного чтения.",
  SUITE_NAME_INVALID: "Введите название набора: от 1 до 64 символов без управляющих знаков.", SUITE_NAME_EXISTS: "Такое название уже есть. Укажите другое или обновите выбранный набор.",
  SUITE_CATALOG_LIMIT_REACHED: "Сохранено слишком много наборов. Удалите ненужный набор.", SUITE_NOT_FOUND: "Набор больше не существует. Обновите страницу.",
  SUITE_SAVE_FAILED: "Сохранение не подтверждено. Обновите страницу перед повторной попыткой.", SUITE_DELETE_FAILED: "Удаление не подтверждено. Обновите страницу перед повторной попыткой."
});
Object.assign(labText.en, {
  savedSuites: "Saved suites", savedSuitesHelp: "Save tests and their settings to repeat a suite with another build. Every run rechecks the build and environment; a saved suite does not establish readiness.",
  chooseSuite: "Choose a suite", suiteName: "Suite name", applySuite: "Use suite", saveNewSuite: "Save new", updateSuite: "Update selected", deleteSuite: "Delete suite",
  suiteSaved: "Suite saved.", suiteApplied: "Suite selected. Prepare a fresh launch for the selected build.", suiteDeleted: "Suite deleted. Current test choices are retained.",
  SUITE_CATALOG_UNAVAILABLE: "Saved suites could not be read. Refresh the page; saving is disabled until a successful read.",
  SUITE_NAME_INVALID: "Enter a suite name: 1 to 64 characters without control characters.", SUITE_NAME_EXISTS: "That name already exists. Choose another name or update the selected suite.",
  SUITE_CATALOG_LIMIT_REACHED: "Too many saved suites. Delete an unused suite.", SUITE_NOT_FOUND: "The suite no longer exists. Refresh the page.",
  SUITE_SAVE_FAILED: "Saving is not confirmed. Refresh the page before retrying.", SUITE_DELETE_FAILED: "Deletion is not confirmed. Refresh the page before retrying."
});
const suiteCatalog = { items: [], available: false, message: null };
Object.assign(labText.ru,{suiteExport:'Скачать текущий выбор (JSON)',suiteImport:'Выбрать набор из файла',suitePortableHelp:'Файл переносит только тесты и их параметры. Импорт заменяет текущий выбор, не запускает проверку и не меняет сохранённые наборы. Для сохранения нажмите «Сохранить новый». Порядок очереди задаёт текущий каталог.',suiteImported:'Выбор загружен из файла. Для сохранения задайте имя и нажмите «Сохранить новый». Перед запуском нужна свежая подготовка.',suiteExported:'Файл набора сформирован и передан браузеру.',suiteDefaultName:'Набор проверок',SUITE_FILE_INVALID:'Не удалось прочитать набор: нужен JSON формата TestLab версии 1, только имя, режим и известные тесты с параметрами.',SUITE_FILE_TOO_LARGE:'Файл набора должен быть не больше 64 КиБ.',SUITE_IMPORT_BUSY:'Выбор не изменён: выполняется другое действие.'});
Object.assign(labText.en,{suiteExport:'Download current choices (JSON)',suiteImport:'Choose suite from file',suitePortableHelp:'The file carries only tests and their settings. Import replaces current choices without starting a run or changing saved suites. Use Save new to persist it. Queue order follows the current catalog.',suiteImported:'Choices loaded from file. Set a name and use Save new to persist them. Prepare a fresh plan before running.',suiteExported:'Suite file prepared and handed to the browser.',suiteDefaultName:'Test suite',SUITE_FILE_INVALID:'Cannot read this suite: use TestLab JSON format version 1, with only a name, mode and known tests/settings.',SUITE_FILE_TOO_LARGE:'Suite file must be at most 64 KiB.',SUITE_IMPORT_BUSY:'Choices were retained: another action is running.'});
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
  lab("lab-suite-save").disabled = busy || !labState.csrf || !suiteCatalog.available || !(trafficCases()).length;
  lab("lab-suite-update").disabled = lab("lab-suite-save").disabled || !hasSelection;
  lab("lab-suite-delete").disabled = busy || !labState.csrf || !suiteCatalog.available || !hasSelection;
  lab('lab-suite-export').disabled=busy||!(trafficCases()).length;
  lab('lab-suite-import').disabled=busy;
  lab('lab-suite-import-file').disabled=busy;
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
  applySuiteChoices(entry);
  suiteCatalog.message = "suiteApplied";
  renderLab();
}

function applySuiteChoices(entry) {
  lab("lab-mode").value = entry.mode;

    const legacy = {tcp_rtt:["tcp-rtt"],tcp_transfer:["tcp-upload","tcp-download"],tcp_rtt_three_modes:["three-modes"],tcp_connections:["tcp-connections"]};
    trafficChoice = {};
    for (const test of entry.tests) for (const id of legacy[test.scenario] || [test.scenario])
      trafficChoice[id] = {selected:true,duration:test.duration,load:test.load};
    localStorage.setItem("testlab-traffic-choice",JSON.stringify(trafficChoice));

  lab("lab-suite-name").value = entry.name;
  labState.plan = null;
  labState.planFailed = false;
  saveTestingChoice();
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
        tests: trafficCases().map(row=>({scenario:row.id,duration:row.duration,load:row.load})) })
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

function suiteChoicesBusy(ignoreOwnAction=false){
  return (!ignoreOwnAction&&labActionActive)||runActive()||trafficState?.execution?.active||trafficActionActive||remoteActionActive;
}
function portableSuite(value){
  const object=row=>row!==null&&typeof row==='object'&&!Array.isArray(row);
  const keys=(row,allowed)=>object(row)&&Object.keys(row).every(key=>allowed.includes(key));
  if(!keys(value,['format','schema_version','name','mode','tests'])||value.format!=='proxybridge-testlab-suite'||value.schema_version!==1||
    typeof value.name!=='string'||!value.name.trim()||value.name.trim().length>64||/[\u0000-\u001f\u007f-\u009f]/.test(value.name)||
    !['local','remote'].includes(value.mode)||!Array.isArray(value.tests))throw new Error('SUITE_FILE_INVALID');
  const local=['tcp_rtt','tcp_transfer','tcp_rtt_three_modes','tcp_connections'];
  const remote=(trafficCatalog?.cases||[]).map(row=>row.id);
  const native=value.tests.some(row=>object(row)&&remote.includes(row.scenario));
  const allowed=native?remote:local;
  if(!value.tests.length||value.tests.length>allowed.length||new Set(value.tests.map(row=>row?.scenario)).size!==value.tests.length||
    value.tests.some(row=>!keys(row,['scenario','duration','load'])||!allowed.includes(row.scenario)||
      !['SHORT','NORMAL','LONG'].includes(row.duration)||!['LOW','HIGH'].includes(row.load)))throw new Error('SUITE_FILE_INVALID');
  return {name:value.name.trim(),mode:value.mode,tests:value.tests.map(row=>({scenario:row.scenario,duration:row.duration,load:row.load}))};
}
function exportSuiteChoices(){
  if(suiteChoicesBusy())return;
  try{
    const mode=lab('lab-mode').value;
    const entry=portableSuite({format:'proxybridge-testlab-suite',schema_version:1,
      name:lab('lab-suite-name').value.trim()||t('suiteDefaultName'),mode,
      tests:trafficCases().map(row=>({scenario:row.id,duration:row.duration,load:row.load}))});
    const blob=new Blob([JSON.stringify({format:'proxybridge-testlab-suite',schema_version:1,...entry},null,2)+'\n'],{type:'application/json;charset=utf-8'});
    if(blob.size>64*1024)throw new Error('SUITE_FILE_TOO_LARGE');
    const url=URL.createObjectURL(blob),anchor=document.createElement('a');
    anchor.href=url;anchor.download=`testlab-suite-${new Date().toISOString().replace(/[:.]/g,'-')}.json`;
    document.body.append(anchor);anchor.click();anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),10000);
    suiteCatalog.message='suiteExported';
  }catch(error){suiteCatalog.message=error.message==='SUITE_FILE_TOO_LARGE'?error.message:'SUITE_FILE_INVALID';}
  renderLab();
}
async function importSuiteChoices(file){
  if(!file)return;
  if(suiteChoicesBusy()){suiteCatalog.message='SUITE_IMPORT_BUSY';renderLab();return;}
  labActionActive=true;renderLab();
  try{
    if(file.size>64*1024)throw new Error('SUITE_FILE_TOO_LARGE');
    const text=new TextDecoder('utf-8',{fatal:true}).decode(await file.arrayBuffer()).replace(/^\ufeff/,'');
    const entry=portableSuite(JSON.parse(text));
    if(suiteChoicesBusy(true))throw new Error('SUITE_IMPORT_BUSY');
    lab('lab-saved-suite').value='';
    applySuiteChoices(entry);
    suiteCatalog.message='suiteImported';
  }catch(error){suiteCatalog.message=['SUITE_FILE_TOO_LARGE','SUITE_IMPORT_BUSY'].includes(error.message)?error.message:'SUITE_FILE_INVALID';}
  finally{labActionActive=false;lab('lab-suite-import-file').value='';renderLab();}
}
lab('lab-suite-export').addEventListener('click',exportSuiteChoices);
lab('lab-suite-import').addEventListener('click',()=>{if(!suiteChoicesBusy())lab('lab-suite-import-file').click();});
lab('lab-suite-import-file').addEventListener('change',event=>importSuiteChoices(event.target.files?.[0]));

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
