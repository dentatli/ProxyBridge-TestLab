Object.assign(labText.ru, {
  remoteHeading: "Удалённая Ubuntu", remoteHelp: "Ubuntu 22.04 / 24.04 / 26.04 LTS с systemd. Вход по ключу под root; служба работает от отдельного непривилегированного пользователя.",
  remoteIp: "IP Ubuntu (пустое поле сохраняет прежний адрес)", remotePort: "SSH-порт", remoteExistingKey: "Путь к существующему приватному ключу (необязательно)",
  remoteIdentity: "Создать или показать ключ TestLab", remoteCopy: "Копировать публичный ключ", remotePublicKey: "Публичный ключ", remoteKeyHelp: "Добавьте публичный ключ в /root/.ssh/authorized_keys на Ubuntu. Приватный ключ остаётся на Windows. Существующий ключ используется повторно.",
  remoteCheck: "Проверить соединение", remoteSetup: "Автоматическая настройка", remoteApply: "Применить этот план", remotePlanHeading: "План настройки", remotePlanHelp: "Будут установлены только показанные компоненты TestLab. Системный firewall автоматически не изменяется. План действителен 10 минут; перед применением условия проверяются повторно.",
  remoteTrustHelp: "Сравните отпечаток с ключом сервера через консоль Ubuntu или другой доверенный источник. Сам ответ SSH не подтверждает подлинность узла.",
  remoteTrustConfirm: "Отпечаток проверен, доверяю этому узлу", remoteReplaceConfirm: "Подтверждаю замену ранее доверенного ключа сервера", remoteTrustButton: "Подтвердить и проверить", remotePlanExpired: "План истёк. Повторите автоматическую настройку.",
  remoteTestGate: "Готовность компонентов и SSH не подтверждают маршрут SOCKS5. Удалённые испытания пока заблокированы до интеграции контроллера и проверки обмена.",
  remoteWorking: "Выполняется операция. Можно перейти на другую страницу; её состояние сохранится до завершения.", remoteSavedHost: "Адрес сохранён.", remoteNoHost: "Укажите IP Ubuntu.", remoteCopied: "Публичный ключ скопирован.", remoteUnavailable: "Не удалось получить состояние. Обновите страницу перед повторной операцией.", remoteFailure: "Операция не завершена. Проверьте IP, порт, ключ, доступность Ubuntu и повторите проверку.",
  remoteStage_CONFIGURING: "Сохранение настроек", remoteStage_IDENTITY: "Подготовка ключа", remoteStage_CHECKING: "Проверка SSH и компонентов", remoteStage_PLANNING: "Подготовка плана", remoteStage_APPLYING: "Установка и проверка службы",
  remote_UNCONFIGURED: "Сохраните адрес и SSH-ключ.", remote_NEEDS_HOST_TRUST: "Нужно подтвердить ключ сервера.", remote_VALIDATION_REQUIRED: "Требуется проверка соединения и компонентов.", remote_STALE: "После перезапуска приложения повторите проверку.", remote_READY: "SSH и установленные компоненты проверены.", remote_PLAN_READY: "SSH проверен. Компоненты нужно установить.", remote_REPAIR_REQUIRED: "SSH проверен. Компоненты требуют настройки или восстановления.", remote_UNSUPPORTED: "Нужны root, Ubuntu 22.04 / 24.04 / 26.04 LTS и systemd.", remote_ERROR: "SSH или условия установки не прошли проверку.",
  SSH_PORT_INVALID: "SSH-порт должен быть от 1 до 65535.", REMOTE_IP_INVALID: "Введите IP удалённой Ubuntu.", SSH_KEY_PATH_INVALID: "Нужен существующий локальный ключ вне репозитория, без ссылок и сетевых путей.", SSH_KEY_TOOL_FAILED: "Ключ не удалось прочитать. Проверьте файл и права; ключ с паролем не поддерживается.", WINDOWS_OPENSSH_NOT_INSTALLED: "Установите клиент Windows OpenSSH.", REMOTE_OPERATION_ACTIVE: "Операция уже выполняется.", REMOTE_STORAGE_OR_LEASE_ERROR: "Настройка занята другим процессом или хранилище недоступно.", SERVER_PLAN_EXPIRED: "План истёк. Подготовьте новый.", SERVER_PLAN_INPUT_CHANGED: "Условия изменились. Подготовьте новый план.", SERVER_PORT_CONFLICT: "Порты заняты другой службой. Освободите их и повторите проверку.", UBUNTU_PLATFORM_CHANGED: "Платформа изменилась после подготовки плана. Повторите проверку.", remoteListeners: "Ожидаемые слушатели", remotePorts: "Резерв портов", remotePackages: "Пакеты", remoteFiles: "Каталоги", remotePlugins: "Протоколы", remoteNoPackages: "Дополнительные пакеты не нужны"
});
Object.assign(labText.en, {
  remoteHeading: "Remote Ubuntu", remoteHelp: "Ubuntu 22.04 / 24.04 / 26.04 LTS with systemd. SSH key login as root; the service runs as a dedicated unprivileged user.",
  remoteIp: "Ubuntu IP (leave blank to keep the saved address)", remotePort: "SSH port", remoteExistingKey: "Existing private key path (optional)",
  remoteIdentity: "Create or show TestLab key", remoteCopy: "Copy public key", remotePublicKey: "Public key", remoteKeyHelp: "Add the public key to /root/.ssh/authorized_keys on Ubuntu. The private key stays on Windows. An existing identity is reused.",
  remoteCheck: "Check connection", remoteSetup: "Automatic setup", remoteApply: "Apply this plan", remotePlanHeading: "Setup plan", remotePlanHelp: "Only the listed TestLab components will be installed. The system firewall is not changed automatically. The plan expires in 10 minutes; conditions are checked again before applying.",
  remoteTrustHelp: "Compare this fingerprint with the server key using the Ubuntu console or another trusted source. The SSH response alone does not authenticate the host.", remoteTrustConfirm: "I verified the fingerprint and trust this host", remoteReplaceConfirm: "I confirm replacement of the previously trusted host key", remoteTrustButton: "Confirm and check", remotePlanExpired: "Plan expired. Repeat automatic setup.",
  remoteTestGate: "SSH and component health do not prove the SOCKS5 route. Remote tests remain blocked until the controller and exchange checks are integrated.",
  remoteWorking: "Operation in progress. You may navigate to another page; its state remains available until completion.", remoteSavedHost: "Address saved.", remoteNoHost: "Enter the Ubuntu IP.", remoteCopied: "Public key copied.", remoteUnavailable: "State unavailable. Refresh before trying another operation.", remoteFailure: "Operation incomplete. Check the IP, port, key and Ubuntu connectivity, then check again.",
  remoteStage_CONFIGURING: "Saving settings", remoteStage_IDENTITY: "Preparing identity", remoteStage_CHECKING: "Checking SSH and components", remoteStage_PLANNING: "Preparing plan", remoteStage_APPLYING: "Installing and verifying service",
  remote_UNCONFIGURED: "Save an address and SSH key.", remote_NEEDS_HOST_TRUST: "Confirm the server key.", remote_VALIDATION_REQUIRED: "Check the connection and components.", remote_STALE: "Check again after restarting the application.", remote_READY: "SSH and installed components verified.", remote_PLAN_READY: "SSH verified. Components need installation.", remote_REPAIR_REQUIRED: "SSH verified. Components need setup or repair.", remote_UNSUPPORTED: "Root, Ubuntu 22.04 / 24.04 / 26.04 LTS and systemd are required.", remote_ERROR: "SSH or installation prerequisites failed verification.",
  SSH_PORT_INVALID: "SSH port must be between 1 and 65535.", REMOTE_IP_INVALID: "Enter the remote Ubuntu IP.", SSH_KEY_PATH_INVALID: "Use an existing local key outside the repository, without links or network paths.", SSH_KEY_TOOL_FAILED: "Cannot read the key. Check its file and permissions; passphrase-protected keys are not supported.", WINDOWS_OPENSSH_NOT_INSTALLED: "Install Windows OpenSSH client.", REMOTE_OPERATION_ACTIVE: "An operation is already running.", REMOTE_STORAGE_OR_LEASE_ERROR: "Another process owns setup or storage is unavailable.", SERVER_PLAN_EXPIRED: "Plan expired. Prepare a new one.", SERVER_PLAN_INPUT_CHANGED: "Inputs changed. Prepare a new plan.", SERVER_PORT_CONFLICT: "Another service owns required ports. Free them and check again.", UBUNTU_PLATFORM_CHANGED: "Platform changed after planning. Check again.", remoteListeners: "Expected listeners", remotePorts: "Reserved ports", remotePackages: "Packages", remoteFiles: "Directories", remotePlugins: "Protocols", remoteNoPackages: "No additional packages needed"
});

let remoteState = null, remoteActionActive = false, remoteUnavailable = false, remoteNote = null, remoteTimer = null, remoteSetupPending = false;
function renderRemote(busy) {
  lab("lab-remote").hidden = lab("lab-mode").value !== "remote";
  const working = remoteActionActive || remoteState?.busy;
  const blocked = busy || working || remoteUnavailable || !labState.csrf;
  for (const id of ["remote-ip", "remote-port", "remote-key-path", "remote-identity", "remote-check", "remote-setup", "remote-trust-confirm", "remote-replace-confirm"]) lab(id).disabled = blocked;
  const validation = remoteState?.validation, plan = remoteState?.plan;
  lab("remote-trust").hidden = validation?.state !== "NEEDS_HOST_TRUST";
  lab("remote-fingerprints").textContent = validation?.fingerprints?.join("\n") || "";
  lab("remote-replace-label").hidden = !validation?.hostKeyChanged;
  lab("remote-trust-button").disabled = blocked || !lab("remote-trust-confirm").checked || (validation?.hostKeyChanged && !lab("remote-replace-confirm").checked);
  lab("remote-public-label").hidden = !remoteState?.publicKey;
  lab("remote-public").value = remoteState?.publicKey || "";
  lab("remote-copy").disabled = !remoteState?.publicKey;
  lab("remote-plan").hidden = !plan;
  lab("remote-plan-summary").textContent = plan ? `${plan.target}\n${t("remotePackages")}: ${plan.packages.join(", ") || t("remoteNoPackages")}\n${t("remoteFiles")}: ${plan.paths.join(", ")}\n${t("remotePorts")}: TCP ${plan.tcpPorts.join(", ")} · UDP ${plan.udpPorts.join(", ")}\n${t("remotePlugins")}: ${plan.protocolPlugins.join(", ")}` : "";
  if (plan) lab("remote-plan-summary").textContent += `\n${t("remoteListeners")}: TCP ${(plan.listenerTcpPorts || plan.tcpPorts).join(", ")} · UDP ${(plan.listenerUdpPorts || plan.udpPorts).join(", ")}`;
  const expired = plan && Date.parse(plan.expiresUtc) <= Date.now();
  lab("remote-apply").disabled = blocked || !plan || expired;
  let state = remoteState?.error ? "ERROR" : remoteState?.apply?.state || validation?.state || remoteState?.status?.state || "UNCONFIGURED";
  if (state === "READY") state = remoteState.status.state;
  lab("remote-status").textContent = working ? `${labText[labLanguage]["remoteStage_" + remoteState?.stage] || ""}. ${t("remoteWorking")}` : `${t(remoteState?.hostSaved ? "remoteSavedHost" : "remoteNoHost")} ${expired ? t("remotePlanExpired") : t("remote_" + state)}`;
  const error = remoteState?.error;
  lab("remote-error").textContent = remoteUnavailable ? t("remoteUnavailable") : error ? (labText[labLanguage][error] || t("remoteFailure")) : remoteNote ? t(remoteNote) : state === "ERROR" || remoteState?.apply?.state === "REPAIR_REQUIRED" ? t("remoteFailure") : "";
}

async function loadRemote() {
  try {
    const response = await fetch("/api/v1/lab/remote", { cache: "no-store", signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error("remote");
    remoteState = await response.json(); remoteUnavailable = false;
    if (document.activeElement !== lab("remote-port")) lab("remote-port").value = remoteState.port;
  } catch { remoteUnavailable = true; }
  clearTimeout(remoteTimer);
  if (remoteState?.busy || remoteState?.hostSaved) remoteTimer = setTimeout(async () => { await loadRemote(); renderLab(); }, remoteState?.busy ? 2000 : 15000);
}

async function remotePost(action, request = {}) {
  const response = await fetch(`/api/v1/lab/remote/${action}`, { method: "POST", headers: { "Content-Type": "application/json", "X-TestLab-CSRF": labState.csrf }, body: JSON.stringify(request) });
  const data = await response.json();
  if (data.status) remoteState = data;
  if (!response.ok || data.error) throw new Error(data.error || "remoteFailure");
}
async function saveRemoteInput() {
  await remotePost("configure", { host: lab("remote-ip").value.trim(), port: Number(lab("remote-port").value), private_key_path: lab("remote-key-path").value.trim() || null });
  lab("remote-key-path").value = "";
}
async function remoteAction(action) {
  if (remoteActionActive || remoteState?.busy || labActionActive || runActive() || remoteUnavailable) return;
  remoteActionActive = true; remoteNote = null;
  labState.plan = null; labState.planFailed = false;
  renderLab();
  clearTimeout(remoteTimer);
  remoteTimer = setTimeout(async () => { await loadRemote(); renderLab(); }, 2000);
  try {
    if (["identity", "check", "setup"].includes(action)) await saveRemoteInput();
    if (action === "identity") await remotePost("identity");
    if (action === "check" || action === "setup") {
      remoteSetupPending = action === "setup";
      lab("remote-trust-confirm").checked = false; lab("remote-replace-confirm").checked = false;
      await remotePost("check");
      if (action === "setup" && ["READY", "PLAN_READY", "REPAIR_REQUIRED"].includes(remoteState.validation?.state)) await remotePost("plan");
    }
    if (action === "trust") {
      await remotePost("check", { trust_token: remoteState.validation?.trustToken, confirm_host_trust: lab("remote-trust-confirm").checked, replace_changed_host_key: lab("remote-replace-confirm").checked });
      lab("remote-trust-confirm").checked = false; lab("remote-replace-confirm").checked = false;
      if (remoteSetupPending && ["READY", "PLAN_READY", "REPAIR_REQUIRED"].includes(remoteState.validation?.state)) await remotePost("plan");
    }
    if (action === "apply") await remotePost("apply", { plan_id: remoteState.plan?.planId, confirmed: true });
  } catch (error) { remoteNote = labText[labLanguage][error.message] ? error.message : "remoteFailure"; }
  finally { remoteActionActive = false; await loadRemote(); renderLab(); }
}
for (const [id, action] of [["remote-identity", "identity"], ["remote-check", "check"], ["remote-setup", "setup"], ["remote-trust-button", "trust"], ["remote-apply", "apply"]]) lab(id).addEventListener("click", () => remoteAction(action));
for (const id of ["remote-trust-confirm", "remote-replace-confirm"]) lab(id).addEventListener("change", renderLab);
lab("remote-copy").addEventListener("click", async () => {
  try { await navigator.clipboard.writeText(remoteState?.publicKey || ""); remoteNote = "remoteCopied"; }
  catch { remoteNote = "remoteFailure"; }
  renderLab();
});
