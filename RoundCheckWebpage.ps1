# RoundCheckWebpage v2.0.0
# Windows PowerShell 5.1 / .NET Framework / WinForms / Win32 API
# Source-only, no EXE, no AutoHotkey dependency.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Root 'Configuration.txt'
$script:LegacyConfigPath = Join-Path $script:Root 'Config.ini'
$script:LogPath = Join-Path (Join-Path $script:Root '_Logs') 'error.log'
$script:RunMutex = $null
$script:StopRequest = $null
$script:LockOwned = $false
$script:AppContext = $null
$script:Tray = $null
$script:TrayMenu = $null
$script:PulseTimer = $null
$script:Settings = $null
$script:Clock = $null
$script:NextDueMs = 0L
$script:LastOpenMs = -5000L
$script:Opening = $false
$script:Paused = $false
$script:DpiStatus = 'Unknown'
$script:ExitCode = 0

function Write-Diagnostic {
    param([string]$Text)
    try {
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:LogPath))
        $record = '[' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $Text + [Environment]::NewLine
        [System.IO.File]::AppendAllText($script:LogPath, $record, [System.Text.Encoding]::UTF8)
    }
    catch {
        # Logging is best-effort; UI errors also notify the user.
    }
}

function Parse-Boolean {
    param([string]$Value, [string]$Name)
    if ($Value -ieq 'true' -or $Value -eq '1') { return $true }
    if ($Value -ieq 'false' -or $Value -eq '0') { return $false }
    throw "$Name 必须填写 true 或 false（收到 '$Value'）。"
}

function Test-WebUrl {
    param([string]$Url, [string]$Description)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or
        ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or
        [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "$Description 不是有效的 http:// 或 https:// 完整网址：$Url"
    }
}

function Convert-LegacyConfig {
    # One-time conversion if Configuration.txt is absent and v1 Config.ini is present.
    # Never overwrite an existing Configuration.txt; never modify the old Config.ini.
    if ([System.IO.File]::Exists($script:ConfigPath)) { return }
    if (-not [System.IO.File]::Exists($script:LegacyConfigPath)) {
        throw "找不到 Configuration.txt。请将它放在 Main.cmd 同一目录。"
    }

    $validKeys = @('IntervalMinutes', 'OpenOnStart', 'Url1Enabled', 'Url1', 'Url2Enabled', 'Url2')
    $values = @{}
    $lineNo = 0
    foreach ($raw in (Get-Content -LiteralPath $script:LegacyConfigPath -Encoding UTF8 -ErrorAction Stop)) {
        $lineNo++
        $line = $raw.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')) { continue }
        $equalAt = $line.IndexOf('=')
        if ($equalAt -lt 1) { throw "旧 Config.ini 第 $lineNo 行不是 Key=Value 格式。" }
        $key = $line.Substring(0, $equalAt).Trim()
        $value = $line.Substring($equalAt + 1).Trim()
        if ($validKeys -notcontains $key) { throw "旧 Config.ini 第 $lineNo 行包含未知字段：$key。" }
        if ($values.ContainsKey($key)) { throw "旧 Config.ini 第 $lineNo 行重复定义 $key。" }
        $values[$key] = $value
    }
    foreach ($key in $validKeys) {
        if (-not $values.ContainsKey($key)) { throw "旧 Config.ini 缺少字段：$key。" }
    }
    $minutes = 0
    if (-not [int]::TryParse($values['IntervalMinutes'], [ref]$minutes) -or
        $minutes -lt 1 -or $minutes -gt 43200) {
        throw '旧 Config.ini 的 IntervalMinutes 必须为 1 至 43200 的整数。'
    }
    $startAtLaunch = Parse-Boolean $values['OpenOnStart'] '旧 OpenOnStart'
    $enabled1 = Parse-Boolean $values['Url1Enabled'] '旧 Url1Enabled'
    $enabled2 = Parse-Boolean $values['Url2Enabled'] '旧 Url2Enabled'
    Test-WebUrl $values['Url1'] '旧 Url1'
    Test-WebUrl $values['Url2'] '旧 Url2'
    if (-not $enabled1 -and -not $enabled2) {
        throw '旧 Config.ini 未启用任何 URL，无法迁移。'
    }

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('# RoundCheckWebpage v2.0.0：自动从同目录旧 Config.ini 迁移')
    $lines.Add('# 每行一个网址。行首 # 或 ; 表示暂不打开。')
    $lines.Add('IntervalMinutes=' + $minutes)
    $lines.Add('OpenOnStart=' + $startAtLaunch.ToString().ToLowerInvariant())
    $lines.Add('')
    foreach ($suffix in @('1', '2')) {
        $url = [string]$values['Url' + $suffix]
        $enabled = if ($suffix -eq '1') { $enabled1 } else { $enabled2 }
        if ($enabled) { $lines.Add($url) }
        else { $lines.Add('# ' + $url) }
    }

    $tempPath = $script:ConfigPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [System.IO.File]::WriteAllLines($tempPath, $lines.ToArray(), ([System.Text.UTF8Encoding]::new($true)))
        try {
            [System.IO.File]::Move($tempPath, $script:ConfigPath)
        }
        catch {
            # Concurrent launch may have completed migration first; prefer the file it created.
            if (-not [System.IO.File]::Exists($script:ConfigPath)) { throw }
        }
    }
    finally {
        if ([System.IO.File]::Exists($tempPath)) {
            try { [System.IO.File]::Delete($tempPath) } catch { }
        }
    }
}

function Read-Settings {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) {
        throw "找不到配置文件：$Path。"
    }

    $minutes = $null
    $onStart = $true
    $seenOnStart = $false
    $urls = New-Object 'System.Collections.Generic.List[string]'
    $lineNumber = 0
    foreach ($rawLine in (Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)) {
        $lineNumber++
        $line = $rawLine.Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }

        if ($line -match '^https?://') {
            Test-WebUrl $line "Configuration.txt 第 $lineNumber 行"
            $urls.Add($line)
            continue
        }

        $equalAt = $line.IndexOf('=')
        if ($equalAt -lt 1) {
            throw "Configuration.txt 第 $lineNumber 行无效。请写完整 http(s):// 网址，或 IntervalMinutes=数字。"
        }
        $key = $line.Substring(0, $equalAt).Trim()
        $value = $line.Substring($equalAt + 1).Trim()
        if ($key -ieq 'IntervalMinutes') {
            if ($null -ne $minutes) { throw "Configuration.txt 第 $lineNumber 行重复定义 IntervalMinutes。" }
            $parsed = 0
            if (-not [int]::TryParse($value, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 43200) {
                throw "Configuration.txt 第 $lineNumber 行 IntervalMinutes 必须是 1 至 43200 的整数分钟。"
            }
            $minutes = $parsed
        }
        elseif ($key -ieq 'OpenOnStart') {
            if ($seenOnStart) { throw "Configuration.txt 第 $lineNumber 行重复定义 OpenOnStart。" }
            $onStart = Parse-Boolean $value 'OpenOnStart'
            $seenOnStart = $true
        }
        else {
            throw "Configuration.txt 第 $lineNumber 行包含未知字段 '$key'。网址请直接一行写一个，无需 URL= 前缀。"
        }
    }

    if ($null -eq $minutes) { throw 'Configuration.txt 缺少 IntervalMinutes=分钟数。' }
    if ($urls.Count -eq 0) { throw 'Configuration.txt 没有任何启用的网址，请至少写一行 http(s):// URL。' }
    return [pscustomobject]@{
        IntervalMinutes = [int]$minutes
        IntervalMs      = ([long]$minutes * 60000L)
        OpenOnStart      = [bool]$onStart
        Urls             = $urls.ToArray()
    }
}

function Enable-PerMonitorV2Dpi {
    # Must execute on the STA thread before WinForms creates any HWND.
    Add-Type -Language CSharp -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class RoundCheckWebpageDpi {
    private static readonly IntPtr Pmv2 = new IntPtr(-4);
    [DllImport("user32.dll", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll", SetLastError=true)]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")]
    private static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AreDpiAwarenessContextsEqual(IntPtr first, IntPtr second);

    public static string Enable() {
        try {
            bool processSet = SetProcessDpiAwarenessContext(Pmv2);
            if (!processSet) {
                // The powershell.exe manifest may have already set process-wide DPI.
                // Set the tray UI thread to PMv2 when process-level change is denied.
                SetThreadDpiAwarenessContext(Pmv2);
            }
            return AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), Pmv2)
                ? "PerMonitorV2" : "Unavailable";
        }
        catch (EntryPointNotFoundException) { return "Unavailable (older Windows)"; }
        catch (DllNotFoundException) { return "Unavailable (user32.dll)"; }
    }
}
'@
    return [RoundCheckWebpageDpi]::Enable()
}

function Get-InstanceNames {
    param([string]$ScriptFile, [string]$Prefix)
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $script:Root $ScriptFile)).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullPath)) }
    finally { $sha.Dispose() }
    $hex = [BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 24)
    $mutexName = 'Local\' + $Prefix + '_' + $hex
    $stopName = 'Local\' + $Prefix + '_Stop_' + $hex
    return @($mutexName, $stopName)
}

function Acquire-SingleInstance {
    $names = Get-InstanceNames 'RoundCheckWebpage.ps1' 'RoundCheckWebpage'
    $script:RunMutex = [System.Threading.Mutex]::new($false, [string]$names[0])
    $script:StopRequest = [System.Threading.EventWaitHandle]::new($false, [System.Threading.EventResetMode]::AutoReset, [string]$names[1])
    try { $script:LockOwned = $script:RunMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $script:LockOwned = $true }
    if (-not $script:LockOwned) {
        [void]$script:StopRequest.Set()
        try { $script:LockOwned = $script:RunMutex.WaitOne(8000) }
        catch [System.Threading.AbandonedMutexException] { $script:LockOwned = $true }
        if (-not $script:LockOwned) {
            throw '旧版 RoundCheckWebpage 实例在 8 秒内没有退出。本次启动已取消，以防出现多个定时器。'
        }
    }
    # Consume any stale auto-reset stop signal after taking ownership.
    [void]$script:StopRequest.WaitOne(0)
}

function Stop-LegacyInSameFolder {
    # v1 uses a different mutex prefix and filename. We can safely signal it only
    # when it belongs to the SAME physical directory. Different folders need manual exit.
    $names = Get-InstanceNames 'Round_Check_GT_Ticket.ps1' 'RoundCheckGT'
    $oldMutex = $null
    $oldStop = $null
    $ownedOld = $false
    try {
        try { $oldMutex = [System.Threading.Mutex]::OpenExisting([string]$names[0]) }
        catch [System.Threading.WaitHandleCannotBeOpenedException] { return }
        try { $ownedOld = $oldMutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] { $ownedOld = $true }
        if ($ownedOld) { return } # Legacy mutex exists but is no longer owned.
        try { $oldStop = [System.Threading.EventWaitHandle]::OpenExisting([string]$names[1]) }
        catch [System.Threading.WaitHandleCannotBeOpenedException] {
            throw '检测到旧 v1 进程，但找不到其退出事件。请手动退出旧版后重试。'
        }
        [void]$oldStop.Set()
        try { $ownedOld = $oldMutex.WaitOne(8000) }
        catch [System.Threading.AbandonedMutexException] { $ownedOld = $true }
        if (-not $ownedOld) {
            throw '同目录旧版 v1.0.0 在 8 秒内没有退出。请先从旧版托盘退出。'
        }
    }
    finally {
        if ($ownedOld -and $null -ne $oldMutex) {
            try { $oldMutex.ReleaseMutex() } catch { }
        }
        if ($null -ne $oldStop) { $oldStop.Dispose() }
        if ($null -ne $oldMutex) { $oldMutex.Dispose() }
    }
}

function Reset-NextDue {
    $script:NextDueMs = [long]$script:Clock.ElapsedMilliseconds + [long]$script:Settings.IntervalMs
}

function Update-TrayUi {
    if ($null -eq $script:Tray) { return }
    $status = if ($script:Paused) { '已暂停' } else { '运行中' }
    $num = $script:Settings.Urls.Count
    $script:StatusItem.Text = "状态：$status；$($script:Settings.IntervalMinutes) 分钟；$num 个网址"
    $script:PauseItem.Text = if ($script:Paused) { '恢复定时打开' } else { '暂停定时打开' }
    $script:Tray.Icon = if ($script:Paused) { [System.Drawing.SystemIcons]::Warning } else { [System.Drawing.SystemIcons]::Application }
    $script:Tray.Text = "RoundCheckWebpage | $status | $($script:Settings.IntervalMinutes) min | $num URL"
}

function Show-TrayError {
    param([string]$Summary, [string]$Details)
    Write-Diagnostic ($Summary + ' | ' + $Details)
    if ($null -ne $script:Tray) {
        try {
            $message = $Details
            if ($message.Length -gt 230) { $message = $message.Substring(0, 230) + '...' }
            $script:Tray.ShowBalloonTip(6000, $Summary, $message, [System.Windows.Forms.ToolTipIcon]::Error)
        }
        catch { }
    }
}

function Invoke-OpenPages {
    param([string]$Reason, [bool]$IgnoreCooldown = $false)
    if ($script:Opening) { return $false }
    $now = [long]$script:Clock.ElapsedMilliseconds
    if (-not $IgnoreCooldown -and (($now - $script:LastOpenMs) -lt 2000L)) { return $false }
    $script:Opening = $true
    $script:LastOpenMs = $now
    try {
        $errors = New-Object 'System.Collections.Generic.List[string]'
        foreach ($url in $script:Settings.Urls) {
            try {
                # URLs are sent through the Windows shell to the default browser.
                $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                $startInfo.FileName = $url
                $startInfo.UseShellExecute = $true
                $process = [System.Diagnostics.Process]::Start($startInfo)
                if ($null -ne $process) { $process.Dispose() }
            }
            catch { $errors.Add("$url ： $($_.Exception.Message)") }
        }
        if ($errors.Count -gt 0) { Show-TrayError '部分网址打开失败' ($errors -join ' | ') }
        return $true
    }
    finally { $script:Opening = $false }
}

function Start-TrayApp {
    $script:Clock = [System.Diagnostics.Stopwatch]::StartNew()
    $script:AppContext = New-Object System.Windows.Forms.ApplicationContext
    $script:TrayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $script:StatusItem = $script:TrayMenu.Items.Add('状态：启动中')
    $script:StatusItem.Enabled = $false
    [void]$script:TrayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $script:RunNowItem = $script:TrayMenu.Items.Add('立即打开全部网址')
    $script:PauseItem = $script:TrayMenu.Items.Add('暂停定时打开')
    [void]$script:TrayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $script:ReloadItem = $script:TrayMenu.Items.Add('重新读取 Configuration.txt')
    $script:EditItem = $script:TrayMenu.Items.Add('用记事本编辑 Configuration.txt')
    [void]$script:TrayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $script:ExitItem = $script:TrayMenu.Items.Add('退出 RoundCheckWebpage')

    $script:Tray = New-Object System.Windows.Forms.NotifyIcon
    $script:Tray.ContextMenuStrip = $script:TrayMenu
    Update-TrayUi

    $script:RunNowItem.add_Click({
        try {
            if (Invoke-OpenPages 'Manual') {
                if (-not $script:Paused) { Reset-NextDue }
            }
        }
        catch { Show-TrayError '手动打开网页失败' $_.Exception.Message }
    })
    $script:Tray.add_DoubleClick({
        try {
            if (Invoke-OpenPages 'ManualDoubleClick') {
                if (-not $script:Paused) { Reset-NextDue }
            }
        }
        catch { Show-TrayError '双击打开网页失败' $_.Exception.Message }
    })
    $script:PauseItem.add_Click({
        try {
            $script:Paused = -not $script:Paused
            if (-not $script:Paused) { Reset-NextDue }
            Update-TrayUi
        }
        catch { Show-TrayError '暂停或恢复失败' $_.Exception.Message }
    })
    $script:ReloadItem.add_Click({
        try {
            $newSettings = Read-Settings $script:ConfigPath
            $script:Settings = $newSettings # All-or-nothing assignment after validation.
            Reset-NextDue
            Update-TrayUi
            $script:Tray.ShowBalloonTip(2500, '配置已更新', '下一轮从当前时刻重新计时，不会立即打开。', [System.Windows.Forms.ToolTipIcon]::Info)
        }
        catch { Show-TrayError '配置更新失败（继续使用原设置）' $_.Exception.Message }
    })
    $script:EditItem.add_Click({
        try {
            $startInfo = New-Object System.Diagnostics.ProcessStartInfo
            $startInfo.FileName = Join-Path $env:WINDIR 'System32\notepad.exe'
            $startInfo.Arguments = '"' + $script:ConfigPath + '"'
            $startInfo.UseShellExecute = $true
            $proc = [System.Diagnostics.Process]::Start($startInfo)
            if ($null -ne $proc) { $proc.Dispose() }
        }
        catch { Show-TrayError '打开配置文件失败' $_.Exception.Message }
    })
    $script:ExitItem.add_Click({ $script:AppContext.ExitThread() })

    $script:PulseTimer = New-Object System.Windows.Forms.Timer
    $script:PulseTimer.Interval = 500
    $script:PulseTimer.add_Tick({
        try {
            if ($script:StopRequest.WaitOne(0)) {
                $script:AppContext.ExitThread()
                return
            }
            if ($script:Paused) { return }
            if ($script:Clock.ElapsedMilliseconds -ge $script:NextDueMs) {
                # Reset after this batch completes, never queue a burst after sleep or slow browsers.
                try { [void](Invoke-OpenPages 'Timer') }
                finally { Reset-NextDue }
            }
        }
        catch { Show-TrayError '定时打开网页失败' $_.Exception.Message }
    })

    $script:Tray.Visible = $true
    # Only retire a same-folder v1 instance after our tray UI is constructed.
    Stop-LegacyInSameFolder
    if ($script:DpiStatus -ne 'PerMonitorV2') {
        Show-TrayError 'DPI 警告' "Per-Monitor V2 未启用：$script:DpiStatus。"
    }
    if ($script:Settings.OpenOnStart) { [void](Invoke-OpenPages 'Startup' $true) }
    Reset-NextDue
    $script:PulseTimer.Start()
    [System.Windows.Forms.Application]::Run($script:AppContext)
}

try {
    $script:DpiStatus = Enable-PerMonitorV2Dpi
    # Check configuration BEFORE asking an existing good instance to exit.
    Convert-LegacyConfig
    $script:Settings = Read-Settings $script:ConfigPath
    Acquire-SingleInstance
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    Start-TrayApp
}
catch {
    $script:ExitCode = 1
    Write-Diagnostic ('Fatal: ' + $_.Exception.ToString())
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show(
            "RoundCheckWebpage 启动失败：`r`n`r`n" + $_.Exception.Message + "`r`n`r`n详情：_Logs\error.log",
            'RoundCheckWebpage v2.0.0',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    catch { [Console]::Error.WriteLine($_.Exception.ToString()) }
}
finally {
    if ($null -ne $script:PulseTimer) {
        try { $script:PulseTimer.Stop(); $script:PulseTimer.Dispose() } catch { }
    }
    if ($null -ne $script:Tray) {
        try { $script:Tray.Visible = $false; $script:Tray.Dispose() } catch { }
    }
    if ($null -ne $script:TrayMenu) {
        try { $script:TrayMenu.Dispose() } catch { }
    }
    if ($null -ne $script:AppContext) {
        try { $script:AppContext.Dispose() } catch { }
    }
    if ($null -ne $script:StopRequest) {
        try { $script:StopRequest.Dispose() } catch { }
    }
    if ($null -ne $script:RunMutex) {
        if ($script:LockOwned) { try { $script:RunMutex.ReleaseMutex() } catch { } }
        try { $script:RunMutex.Dispose() } catch { }
    }
}

if ($script:ExitCode -ne 0) { exit $script:ExitCode }
