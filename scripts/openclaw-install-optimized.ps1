#requires -Version 5.1
$ErrorActionPreference = 'Stop'

param(
  [ValidateSet('auto','cn','global')]
  [string]$Profile = 'auto',
  [switch]$CheckOnly,
  [string]$NpmRegistry = '',
  [int[]]$ProxyPorts = @(10808,7897),
  [switch]$InstallBuildTools
)

function Log($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }

function Test-Url($url){
  try { (Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 12).StatusCode -ge 200 | Out-Null; return $true }
  catch { return $false }
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

function Ensure-Node22 {
  $node = Get-Command node -ErrorAction SilentlyContinue
  if($node){
    $major = [int]((node -v).TrimStart('v').Split('.')[0])
    if($major -ge 22){ Ok "Node OK: $(node -v)"; return }
  }

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if(-not $winget){ throw 'winget not found. Please install App Installer from Microsoft Store.' }
  Log 'Installing Node.js LTS via winget'
  winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements --silent | Out-Null
}

function Ensure-OpenClaw {
  if(-not $NpmRegistry){
    $candidates = @(
      'https://registry.npmjs.org/openclaw',
      'https://registry.npmmirror.com/openclaw',
      'https://mirrors.tencent.com/npm/openclaw',
      'https://repo.huaweicloud.com/repository/npm/openclaw'
    )
    $hit = $candidates | Where-Object { Test-Url $_ } | Select-Object -First 1
    if($hit -match 'npmmirror'){ $script:NpmRegistry='https://registry.npmmirror.com' }
    elseif($hit -match 'tencent'){ $script:NpmRegistry='https://mirrors.tencent.com/npm' }
    elseif($hit -match 'huaweicloud'){ $script:NpmRegistry='https://repo.huaweicloud.com/repository/npm' }
    else { $script:NpmRegistry='https://registry.npmjs.org' }
  }
  npm config set registry $NpmRegistry | Out-Null
  Ok "npm registry: $NpmRegistry"

  Log 'Installing openclaw globally'
  npm install -g openclaw --no-fund --no-audit
  Ok "openclaw: $(openclaw --version)"
}

Log "Profile=$Profile CheckOnly=$CheckOnly"

if($Profile -eq 'cn'){
  if(-not $NpmRegistry){ $NpmRegistry = 'https://registry.npmmirror.com' }
}

$proxy = Get-WindowsProxy
if(-not $proxy){ $proxy = Get-ReachableLocalProxy }
if($proxy){
  $env:HTTP_PROXY = $proxy
  $env:HTTPS_PROXY = $proxy
  $env:ALL_PROXY = $proxy
  $env:NODE_USE_ENV_PROXY = '1'
  Ok "Proxy detected: $proxy"
}

$endpoints = @(
  'https://openclaw.ai/install.ps1',
  'https://registry.npmjs.org/openclaw',
  'https://registry.npmmirror.com/openclaw',
  'https://mirrors.tencent.com/npm/openclaw',
  'https://repo.huaweicloud.com/repository/npm/openclaw'
)
foreach($u in $endpoints){ if(Test-Url $u){ Ok "reachable: $u" } else { Warn "unreachable: $u" } }

if($CheckOnly){
  Write-Host "Node: $((Get-Command node -ErrorAction SilentlyContinue | ForEach-Object {node -v}) -join '')"
  Write-Host "npm: $((Get-Command npm -ErrorAction SilentlyContinue | ForEach-Object {npm -v}) -join '')"
  Write-Host "openclaw: $((Get-Command openclaw -ErrorAction SilentlyContinue | ForEach-Object {openclaw --version}) -join '')"
  exit 0
}

Ensure-Node22
Ensure-OpenClaw

Write-Host "Done. Next: openclaw onboard --install-daemon" -ForegroundColor Green
