param([Parameter(Mandatory=$true)][string]$SmokeDirectory,
      [Parameter(Mandatory=$true)][string]$Binary)
$ErrorActionPreference = 'Stop'
if (Test-Path $SmokeDirectory) { throw 'Use a new directory for each smoke run.' }
New-Item -ItemType Directory $SmokeDirectory | Out-Null
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FourfunSmokeWindow {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
$form = New-Object Windows.Forms.Form
$form.Text = '4fun minimized smoke target'
$form.Size = New-Object Drawing.Size(800, 500)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::DarkSlateBlue
$label = New-Object Windows.Forms.Label
$label.Dock = 'Fill'
$label.TextAlign = 'MiddleCenter'
$label.Font = New-Object Drawing.Font('Arial', 64)
$label.ForeColor = [Drawing.Color]::White
$form.Controls.Add($label)
$script:count = 0
$script:lastStage = ''
$script:started = $false
$script:elapsed = [Diagnostics.Stopwatch]::StartNew()
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
  $script:count++
  $label.Text = "FRAME $script:count"
  if (!$script:started) {
    $script:started = $true
    $form.WindowState = 'Minimized'
    Start-Process -FilePath $Binary -WorkingDirectory (Split-Path $Binary) | Out-Null
  }
  $statusPath = Join-Path $SmokeDirectory 'status.json'
  if (Test-Path $statusPath) {
    try { $status = Get-Content $statusPath -Raw | ConvertFrom-Json } catch { return }
    if ($status.stage -ne $script:lastStage) {
      $script:lastStage = $status.stage
      switch ($status.stage) {
        'waiting' {
          $form.WindowState = 'Normal'
          [FourfunSmokeWindow]::ShowWindow($form.Handle, 9) | Out-Null
          $form.Activate()
          [FourfunSmokeWindow]::SetForegroundWindow($form.Handle) | Out-Null
        }
        'captured_first' {
          $form.WindowState = 'Minimized'
          [IO.File]::WriteAllText((Join-Path $SmokeDirectory 'minimized.marker'), 'ready')
        }
        'restore_requested' {
          $form.WindowState = 'Normal'
          [FourfunSmokeWindow]::ShowWindow($form.Handle, 9) | Out-Null
          $form.Activate()
          [FourfunSmokeWindow]::SetForegroundWindow($form.Handle) | Out-Null
          [IO.File]::WriteAllText((Join-Path $SmokeDirectory 'restored.marker'), 'ready')
        }
        'passed' { $form.Close() }
        'failed' { $form.Close() }
      }
    }
  }
  if ($script:elapsed.Elapsed.TotalSeconds -gt 90) {
    [IO.File]::WriteAllText((Join-Path $SmokeDirectory 'helper-timeout.txt'), 'Smoke helper timed out')
    $form.Close()
  }
})
$form.Add_Shown({ $timer.Start() })
try { [Windows.Forms.Application]::Run($form) } finally { $timer.Dispose(); $form.Dispose() }
