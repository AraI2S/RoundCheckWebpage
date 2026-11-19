# RoundCheckWebpage v2.0.0 - transient, CreateNoWindow launcher.
# The resident PowerShell process has no attached console window.
$ErrorActionPreference = 'Stop'

try {
    $main = Join-Path $PSScriptRoot 'RoundCheckWebpage.ps1'
    if (-not [System.IO.File]::Exists($main)) {
        throw "找不到主程序：$main"
    }

    # Catch PowerShell syntax errors before creating an invisible child process.
    # This uses the built-in PS 5.1 parser, without executing the main program.
    $tokens = $null
    $syntaxErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($main, [ref]$tokens, [ref]$syntaxErrors)
    if ($syntaxErrors.Count -gt 0) {
        $first = $syntaxErrors[0]
        throw "主程序存在 PowerShell 语法错误（第 $($first.Extent.StartLineNumber) 行）：$($first.Message)"
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Sta -File "' + $main + '"'
    $startInfo.WorkingDirectory = $PSScriptRoot
    # These two values, rather than -WindowStyle Hidden, are the critical pair.
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $child = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $child) { throw '无法创建后台 PowerShell 进程。' }
    $child.Dispose()
}
catch {
    $details = "无法启动 RoundCheckWebpage。`r`n`r`n$($_.Exception.Message)"
    try {
        $logDir = Join-Path $PSScriptRoot '_Logs'
        [void][System.IO.Directory]::CreateDirectory($logDir)
        $logPath = Join-Path $logDir 'error.log'
        [System.IO.File]::AppendAllText($logPath, "[$([DateTime]::Now.ToString('s'))] Bootstrap: $details`r`n", [System.Text.Encoding]::UTF8)
    } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        [void][System.Windows.Forms.MessageBox]::Show($details, 'RoundCheckWebpage - 启动错误', 'OK', 'Error')
    }
    catch { [Console]::Error.WriteLine($details) }
    exit 1
}
