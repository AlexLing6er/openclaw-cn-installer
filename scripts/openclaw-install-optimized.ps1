#requires -Version 5.1
$ErrorActionPreference = 'Stop'

param(
  [ValidateSet('auto','cn','global')]
  [string]$Profile = 'auto',
  [ValidateSet('auto','npm','official')]
  [string]$InstallMethod = 'auto',
  [switch]$CheckOnly,
  [string]$NpmRegistry = '',
  [int[]]$ProxyPorts = @(10808,7897),
  [switch]$UseUserNpmPrefix
)

function Log($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[ERR ] $m" -ForegroundColor Red }

# TLS hardening for old PowerShell
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {}

function Test-Url($url){
  try { (Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 12).StatusCode -ge 200 | Out-Null; return $true }
  catch { return $false }
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
    $proxy = (netsh winhttp show proxy | Out-String)
    if($proxy -match 'Proxy Server\(s\)\s*:\s*(.+)'){
      return $Matches[1].Trim()
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
  $proxy = Get-WindowsProxy
  if(-not $proxy){ $proxy = Get-ReachableLocalProxy }
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
}

function Select-NpmRegistry {
  if($NpmRegistry){ return $NpmRegistry }

  if($Profile -eq 'cn'){
    return 'https://registry.npmmirror.com'
  }

  $candidates = @(
    'https://registry.npmjs.org/openclaw',
    'https://registry.npmmirror.com/openclaw',
    'https://mirrors.tencent.com/npm/openclaw',
    'https://repo.huaweicloud.com/repository/npm/openclaw'
  )

  $hit = $candidates | Where-Object { Test-Url $_ } | Select-Object -First 1
  if($hit -match 'npmmirror'){ return 'https://registry.npmmirror.com' }
  if($hit -match 'tencent'){ return 'https://mirrors.tencent.com/npm' }
  if($hit -match 'huaweicloud'){ return 'https://repo.huaweicloud.com/repository/npm' }
  return 'https://registry.npmjs.org'
}

function Setup-UserNpmPrefix {
  $prefix = Join-Path $HOME '.npm-global'
  if(-not (Test-Path $prefix)){ New-Item -ItemType Directory -Force -Path $prefix | Out-Null }
  npm config set prefix $prefix | Out-Null

  $bin = Join-Path $prefix 'node_modules\npm\bin'
  if(-not ($env:Path -like "*$prefix*")){
    $env:Path = "$prefix;$env:Path"
  }
  Ok "Using user npm prefix: $prefix"
}

function Install-OpenClawViaNpm {
  $reg = Select-NpmRegistry
  npm config set registry $reg | Out-Null
  Ok "npm registry: $reg"

  Log 'Installing openclaw via npm'
  try {
    Invoke-WithRetry { npm install -g openclaw --no-fund --no-audit }
  } catch {
    Warn "Global npm install failed, trying user prefix fallback..."
    Setup-UserNpmPrefix
    Invoke-WithRetry { npm install -g openclaw --no-fund --no-audit }
  }

  $cmd = Get-Command openclaw -ErrorAction SilentlyContinue
  if(-not $cmd){
    Warn 'openclaw not found in current PATH. Try opening a new PowerShell and run: openclaw --version'
  } else {
    Ok "openclaw: $(openclaw --version)"
  }
}

function Install-OpenClawOfficial {
  Log 'Installing via official script: https://openclaw.ai/install.ps1'
  Invoke-WithRetry { iwr -useb https://openclaw.ai/install.ps1 | iex }
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

Log "Profile=$Profile InstallMethod=$InstallMethod CheckOnly=$CheckOnly"
Enable-ProxyIfDetected
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
    try {
      Install-OpenClawViaNpm
    } catch {
      Warn "npm method failed: $($_.Exception.Message)"
      Warn 'Falling back to official install script...'
      Install-OpenClawOfficial
    }
  }
}

Write-Host "Done. Next: openclaw onboard --install-daemon" -ForegroundColor Green
