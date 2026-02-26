$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$target = Join-Path $root "target/release"
$output = Join-Path $root "../native"

cargo build --manifest-path (Join-Path $root "Cargo.toml") -p engine_capi --release

New-Item -ItemType Directory -Force -Path (Join-Path $output "windows-x64") | Out-Null

if (Test-Path (Join-Path $target "snow_draw_engine_capi.dll")) {
  Copy-Item (Join-Path $target "snow_draw_engine_capi.dll") (Join-Path $output "windows-x64") -Force
}

if (Test-Path (Join-Path $target "snow_draw_engine_capi.lib")) {
  Copy-Item (Join-Path $target "snow_draw_engine_capi.lib") (Join-Path $output "windows-x64") -Force
}

Copy-Item (Join-Path $root "include/snow_draw_engine.h") $output -Force

Write-Host "Rust desktop ABI artifacts copied to: $output"
