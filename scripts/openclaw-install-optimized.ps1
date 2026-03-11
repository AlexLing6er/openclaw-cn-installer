#requires -Version 5.1

# OpenClaw Windows Installer (high-compat)
# Version: 2026-03-12-winfix3

$Profile = 'auto'
$InstallMethod = 'auto'
$CheckOnly = $false
$NpmRegistry = ''
$ProxyPorts = @(10808,7897)
$UseUserNpmPrefix = $false
$DetectLocalProxyPort = $false

for($i=0; $i -lt $args.Count; $i++){
  $k = "$($args[$i])"
  switch -Regex ($k) {
    '^-Profile$' { if($i+1 -lt $args.Count){ $Profile = "$($args[++$i])" } ; continue }
    '^-InstallMethod$' { if($i+1 -lt $args.Count){ $InstallMethod = "$($args[++$i])" } ; continue }
    '^-NpmRegistry$' { if($i+1 -lt $args.Count){ $NpmRegistry = "$($args[++$i])" } ; continue }
    '^-ProxyPorts$' {
      if($i+1 -lt $args.Count){
        $ProxyPorts = ("$($args[++$i])" -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }
      }
      continue
    }
    '^-CheckOnly$' { $CheckOnly = $true; continue }
    '^-UseUserNpmPrefix$' { $UseUserNpmPrefix = $true; continue }
    '^-DetectLocalProxyPort$' { $DetectLocalProxyPort = $true; continue }
  }
}

if($Profile -notin @('auto','cn','global')){ $Profile='auto' }
if($InstallMethod -notin @('auto','npm','official')){ $InstallMethod='auto' }

$ErrorActionPreference = 'Stop'
$script:RegionHint = 'UNKNOWN'

function Log($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

function Show-Credit {
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Magenta
  Write-Host "By Douhao" -ForegroundColor Magenta
  Write-Host "Blog: https://www.youdiandou.store" -ForegroundColor Magenta
  Write-Host "========================================" -ForegroundColor Magenta
  Write-Host ""
}

function Require-CurlExe {
  $c = Get-Command curl.exe -ErrorAction SilentlyContinue
  if(-not $c){ throw 'curl.exe not found. Please use Windows 10/11 default curl or install it first.' }
}

function Test-Url($url){
  try {
    & curl.exe -L -I --max-time 12 --silent --show-error $url *> $null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Get-Text($url){
  & curl.exe -L --max-time 15 --silent --show-error $url
}

function Measure-UrlMs([string]$Url){
  try {
    $t = & curl.exe -L -I --max-time 10 -o NUL -s -w "%{time_total}" $Url
    if(-not $t){ return $null }
    return [int]([double]$t * 1000)
  } catch {
    return $null
  }
}

function Invoke-WithRetry([scriptblock]$Script,[int]$Retries=3,[int]$DelaySec=2){
  for($i=1; $i -le $Retries; $i++){
    try { & $Script; return }
    catch {
      if($i -eq $Retries){ throw }
      Warn "Retry $i/$Retries failed: $($_.Exception.Message)"
      Start-Sleep -Seconds $DelaySec
    }
  }
}

function Get-WindowsProxy {
  try {
    $raw = (netsh winhttp show proxy | Out-String)
    if($raw -match 'Proxy Server\(s\)\s*:\s*(.+)'){
      $p = $Matches[1].Trim()
      if($p -match '^http=([^;\s]+)'){ return "http://$($Matches[1])" }
      if($p -match '^https=([^;\s]+)'){ return "http://$($Matches[1])" }
      if($p -match '^[\w\.-]+:\d+$'){ return "http://$p" }
      if($p -match '^https?://'){ return $p }
    }
  } catch {}
  return ''
}

function Get-ReachableLocalProxy {
  foreach($p in $ProxyPorts){
    foreach($h in @('127.0.0.1','localhost')){
      try {
        $ok = Test-NetConnection -ComputerName $h -Port $p -WarningAction SilentlyContinue
        if($ok.TcpTestSucceeded){ return "http://$h`:$p" }
      } catch {}
    }
  }
  return ''
}

function Enable-ProxyIfDetected {
  # Proxy = explicitly configured system proxy (WinHTTP/env) by default.
  # Local port probing is optional because a listening port != system proxy enabled.
  $proxy = $env:HTTPS_PROXY
  if(-not $proxy){ $proxy = $env:HTTP_PROXY }
  if(-not $proxy){ $proxy = Get-WindowsProxy }
  if((-not $proxy) -and $DetectLocalProxyPort){ $proxy = Get-ReachableLocalProxy }

  if($proxy){
    $env:HTTP_PROXY = $proxy
    $env:HTTPS_PROXY = $proxy
    $env:ALL_PROXY = $proxy
    $env:NODE_USE_ENV_PROXY = '1'
    Ok "Proxy detected: $proxy"
  } else {
    Log "No proxy detected (this is fine for global networks)."
  }
}

function Ensure-Node22 {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if($node){
    $major = [int]((node -v).TrimStart('v').Split('.')[0])
    if($major -ge 22){ Ok "Node OK: $(node -v)"; return }
    Warn "Node is old: $(node -v)"
  }

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if(-not $winget){ throw 'winget not found. Install App Installer from Microsoft Store, then re-run.' }

  Log 'Installing Node.js LTS via winget'
  Invoke-WithRetry { winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent | Out-Null }

  $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = "$machinePath;$userPath;$env:Path"

  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  if(-not $nodeCmd){
    $candidates = @(
      'C:\Program Files\nodejs\node.exe',
      "$env:LOCALAPPDATA\Programs\nodejs\node.exe"
    )
    foreach($c in $candidates){
      if(Test-Path $c){
        $nodeDir = Split-Path $c -Parent
        $env:Path = "$nodeDir;$env:Path"
        break
      }
    }
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  }

  if(-not $nodeCmd){
    throw 'Node installed but not visible in current PATH. Open a new terminal and rerun installer.'
  }
  Ok "Node OK after install: $(node -v)"
}

function Select-FastestUrl([string[]]$Urls){
  $bestUrl = $null
  $bestMs = [int]::MaxValue
  foreach($u in $Urls){
    $ms = Measure-UrlMs $u
    if($null -ne $ms -and $ms -lt $bestMs){ $bestMs = $ms; $bestUrl = $u }
  }
  return $bestUrl
}

function Select-NpmRegistry {
  if($NpmRegistry){ return $NpmRegistry }

  $official = 'https://registry.npmjs.org/openclaw'
  $m1 = 'https://registry.npmmirror.com/openclaw'
  $m2 = 'https://mirrors.tencent.com/npm/openclaw'
  $m3 = 'https://repo.huaweicloud.com/repository/npm/openclaw'

  $hit = $null
  if($script:Route -eq 'PROXY_OFFICIAL' -or $script:Route -eq 'GLOBAL_DIRECT'){
    if(Test-Url $official){ $hit = $official }
    else { $hit = Select-FastestUrl @($m1,$m2,$m3,$official) }
  } else {
    $hit = Select-FastestUrl @($m1,$m2,$m3)
    if(-not $hit -and (Test-Url $official)){ $hit = $official }
  }

  if($hit -match 'npmmirror'){ return 'https://registry.npmmirror.com' }
  if($hit -match 'tencent'){ return 'https://mirrors.tencent.com/npm' }
  if($hit -match 'huaweicloud'){ return 'https://repo.huaweicloud.com/repository/npm' }
  return 'https://registry.npmjs.org'
}

function Setup-UserNpmPrefix {
  $prefix = Join-Path $HOME '.npm-global'
  if(-not (Test-Path $prefix)){ New-Item -ItemType Directory -Force -Path $prefix | Out-Null }
  npm config set prefix $prefix | Out-Null
  if(-not ($env:Path -like "*$prefix*")){ $env:Path = "$prefix;$env:Path" }
  Ok "Using user npm prefix: $prefix"
}

function Install-OpenClawViaNpm {
  if($UseUserNpmPrefix){ Setup-UserNpmPrefix }

  $reg = Select-NpmRegistry
  npm config set registry $reg | Out-Null
  Ok "npm registry: $reg"

  # Avoid SSH-only git dependency failures in restricted/corporate/CN networks.
  git config --global url."https://github.com/".insteadOf ssh://git@github.com/ | Out-Null
  git config --global url."https://github.com/".insteadOf git@github.com: | Out-Null

  Log 'Installing openclaw via npm'
  try {
    Invoke-WithRetry { npm install -g openclaw --no-fund --no-audit }
  } catch {
    Warn "Global npm install failed, trying user prefix fallback..."
    Setup-UserNpmPrefix
    Invoke-WithRetry { npm install -g openclaw --no-fund --no-audit }
  }

  $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
  if(-not $cmd){ throw 'npm install finished but openclaw command not found in PATH.' }
  Ok "openclaw: $(openclaw --version)"
}

function Install-OpenClawOfficial {
  Log 'Installing via official script: https://openclaw.ai/install.ps1'
  $content = Get-Text 'https://openclaw.ai/install.ps1'
  if(-not $content){ throw 'Failed to download official install script.' }
  Invoke-Expression $content
}

function Get-RegionHint {
  $candidates = @('https://ipapi.co/country','https://ipinfo.io/country')
  foreach($u in $candidates){
    try {
      $v = (Get-Text $u).Trim()
      if($v -eq 'CN'){ return 'CN' }
      if($v -match '^[A-Z]{2}$'){ return 'NON_CN' }
    } catch {}
  }
  return 'UNKNOWN'
}

function Resolve-Route {
  $hasProxy = [bool]($env:HTTPS_PROXY -or $env:HTTP_PROXY)
  $official = Test-Url 'https://registry.npmjs.org/openclaw'

  if($Profile -eq 'cn'){ return 'CN_MIRROR' }
  if($Profile -eq 'global'){ return 'GLOBAL_DIRECT' }

  if($hasProxy){ return 'PROXY_OFFICIAL' }
  $script:RegionHint = Get-RegionHint
  if($script:RegionHint -eq 'CN'){ return 'CN_MIRROR' }
  if($script:RegionHint -eq 'NON_CN'){ return 'GLOBAL_DIRECT' }
  if($official){ return 'GLOBAL_DIRECT' }
  return 'CN_MIRROR'
}

function Print-Decision([string]$Route){
  Write-Host '=== INSTALL DECISION ==='
  Write-Host 'DetectedOS=Windows'
  Write-Host "Profile=$Profile"
  Write-Host "Route=$Route"
  Write-Host "RegionHint=$script:RegionHint"
  Write-Host "Proxy=$($env:HTTPS_PROXY)"
  Write-Host "InstallMethod=$InstallMethod"
  Write-Host '========================'
}

function Check-EndPoints {
  $endpoints = @(
    'https://openclaw.ai/install.ps1',
    'https://registry.npmjs.org/openclaw',
    'https://registry.npmmirror.com/openclaw',
    'https://mirrors.tencent.com/npm/openclaw',
    'https://repo.huaweicloud.com/repository/npm/openclaw'
  )
  foreach($u in $endpoints){ if(Test-Url $u){ Ok "reachable: $u" } else { Warn "unreachable: $u" } }
}

Require-CurlExe
Show-Credit
Log "Profile=$Profile InstallMethod=$InstallMethod CheckOnly=$CheckOnly"
Enable-ProxyIfDetected
$script:Route = Resolve-Route
Print-Decision $script:Route
Check-EndPoints

if($CheckOnly){
  Write-Host "Node: $((Get-Command node -ErrorAction SilentlyContinue | ForEach-Object {node -v}) -join '')"
  Write-Host "npm: $((Get-Command npm -ErrorAction SilentlyContinue | ForEach-Object {npm -v}) -join '')"
  Write-Host "openclaw: $((Get-Command openclaw -ErrorAction SilentlyContinue | ForEach-Object {openclaw --version}) -join '')"
  exit 0
}

Ensure-Node22

switch($InstallMethod){
  'npm' { Install-OpenClawViaNpm }
  'official' { Install-OpenClawOfficial }
  default {
    try { Install-OpenClawViaNpm }
    catch {
      Warn "npm method failed: $($_.Exception.Message)"
      Warn 'Falling back to official install script...'
      Install-OpenClawOfficial
    }
  }
}

Write-Host "Done. Next: openclaw onboard --install-daemon" -ForegroundColor Green
