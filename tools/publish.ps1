# Публикует сайт «Тактичка онлайн» (эта папка, Desktop\taktichka-live) в публичный репозиторий
# sairaila-cmd/taktichka-live → https://sairaila-cmd.github.io/taktichka-live/
# Вход в GitHub — через уже авторизованный gh. Публикуются только пути из списка $paths.
#
#   powershell -File tools\publish.ps1 -Check                    # что уйдёт на GitHub, ничего не отправляя
#   powershell -File tools\publish.ps1 -Message "Что изменено"   # опубликовать
# Файл сохранён в UTF-8 с BOM — иначе Windows PowerShell 5.1 ломает кириллицу.

param(
    [string]$Message = "Обновление сайта",
    [switch]$Check
)
$ErrorActionPreference = "Stop"

$site  = Split-Path -Parent $PSScriptRoot
$repo  = "sairaila-cmd/taktichka-live"
$paths = @("index.html", "README.md", ".gitignore", ".gitattributes", ".github", "css", "js", "img", "vendor", "supabase", "tools", "tests")

if (-not (Test-Path (Join-Path $site ".git"))) {
    git -C $site init --quiet -b main
    if ($LASTEXITCODE) { throw "git init не удался" }
}
git -C $site config user.name "sairaila-cmd"
git -C $site config user.email "342123712+sairaila-cmd@users.noreply.github.com"

# Только существующие пути (папку без файлов git не знает) + удаления уже опубликованных файлов.
$paths = $paths | Where-Object { Test-Path (Join-Path $site $_) }
git -C $site add -- $paths
if ($LASTEXITCODE) { throw "git add не удался" }
git -C $site add -u
if ($LASTEXITCODE) { throw "git add -u не удался" }

# Страховка: личные коды и закрытые ключи не должны попасть в репозиторий.
$staged = git -C $site diff --cached --name-only
$bad = $staged | Where-Object { $_ -match '(^|/)codes[^/]*\.(csv|sql)$' }
$bad += git -C $site grep --cached -l -e "service_role" -- $paths ":!tools/publish.ps1" 2>$null
if ($bad) { git -C $site reset --quiet; throw "Остановлено: в публикацию попали секретные файлы: $($bad -join ', ')" }

git -C $site diff --cached --quiet
$changed = [bool]$LASTEXITCODE
$remote = git -C $site remote
$ErrorActionPreference = "Continue"   # git/gh пишут обычные сообщения в stderr
$unpushed = if ($remote) { git -C $site rev-list --count "origin/main..main" 2>$null } else { git -C $site rev-list --count main 2>$null }
$ErrorActionPreference = "Stop"
if (-not $changed -and -not [int]$unpushed) { Write-Output "Изменений нет: на GitHub та же версия."; exit 0 }

if ($changed) { git -C $site diff --cached --stat }
if ($Check) {
    git -C $site reset --quiet
    Write-Output "Проверка: изменения выше НЕ опубликованы (неотправленных коммитов: $unpushed)."
    exit 0
}

if ($changed) {
    # Сброс кэша браузеров: у всех файлов сайта новый номер версии (?v=…), чтобы после публикации
    # браузеры сразу брали новые файлы, а не держали старые до 10 минут.
    $ver = "v=" + (Get-Date -Format "yyyyMMddHHmm")
    $targets = @(Join-Path $site "index.html") + (Get-ChildItem (Join-Path $site "js") -Recurse -Filter *.js | ForEach-Object { $_.FullName })
    foreach ($f in $targets) {
        $txt = [IO.File]::ReadAllText($f)
        $upd = [regex]::Replace($txt, '\?v=[0-9A-Za-z]+', "?$ver")
        if ($upd -ne $txt) { [IO.File]::WriteAllText($f, $upd, (New-Object Text.UTF8Encoding $false)) }
    }
    git -C $site add -- $paths
    $msg = "$Message`n`nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
    git -C $site commit --quiet -m $msg
    if ($LASTEXITCODE) { throw "git commit не удался" }
}

$ErrorActionPreference = "Continue"
if (-not $remote) {
    gh repo view $repo --json name 2>$null | Out-Null
    if ($LASTEXITCODE) {
        gh repo create $repo --public --description "Тактичка онлайн: учёт фигур, отрядов и боёв" | Out-Null
        if ($LASTEXITCODE) { throw "Не удалось создать репозиторий $repo" }
    }
    git -C $site remote add origin "https://github.com/$repo.git"
}
git -C $site push --quiet -u origin main 2>&1 | Where-Object { $_ -notmatch '^(To |branch |\s)' } | ForEach-Object { "$_" }
if ($LASTEXITCODE) { throw "Не удалось отправить коммит (git push)" }
git -C $site log --oneline -1

# GitHub Pages: включить один раз (ветка main, корень).
gh api "repos/$repo/pages" 2>$null | Out-Null
if ($LASTEXITCODE) {
    gh api -X POST "repos/$repo/pages" -f "source[branch]=main" -f "source[path]=/" | Out-Null
    if ($LASTEXITCODE) { Write-Output "Pages не включились автоматически: Settings → Pages → Branch: main, / (root)." }
    else { Write-Output "GitHub Pages включены." }
}
Write-Output "Опубликовано: https://sairaila-cmd.github.io/taktichka-live/ (обновится через 1-2 минуты)"