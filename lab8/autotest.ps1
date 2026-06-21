
$RUN_JAR = 'java -jar'
$resultFile = 'result_ps1.txt'
$circFile = 'lab6.5.circ'

# 脚本目录和 jar 路径（使用脚本自身路径，避免相对路径问题）
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
$jarPath = Join-Path $scriptDir 'Logisim-ITA.jar'

# 检查 java 命令是否可用
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Host "Error: 'java' not found in PATH. 请安装 Java 或将其加入 PATH。"
    exit 1
}

if (-not (Test-Path $jarPath)) {
    Write-Host "Error: 找不到 $jarPath 。请确认 Logisim-ITA.jar 在脚本目录中。"
    exit 1
}

    # 清空结果文件开始新的运行
$resultPath = Join-Path $scriptDir $resultFile
if (Test-Path $resultPath) {
    Remove-Item $resultPath
}

# 只选择不含 RAM 数据的测试用例（排除以 "_d.hex" 结尾的文件）
$hexFiles = Get-ChildItem -Path (Join-Path $scriptDir 'testcase\*.hex') -File | Where-Object { $_.Name -notlike '*_d.hex' }

foreach ($file in $hexFiles) {
    Write-Host "Testing $($file.Name)"

    # 读取 hex 文件，合并所有词（支持每行多个或单个指令）
    $rawLines = Get-Content $file.FullName | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') }
    $tokens = @()
    foreach ($line in $rawLines) {
        $tokens += ($line -split '\s+')
    }

    # 只保留看起来像十六进制的词，过滤掉文件头（例如 "v2.0 raw"）或其他非指令文本
    $tokens = $tokens | Where-Object { $_ -match '^[0-9A-Fa-f]+$' }

    # 每 8 个指令一行，生成 ROM contents 部分的文本
    $romLines = for ($i = 0; $i -lt $tokens.Count; $i += 8) {
        $end = [math]::Min($i + 7, $tokens.Count - 1)
        $tokens[$i..$end] -join ' '
    }
    $newContents = "addr/data: 16 32`n" + ($romLines -join "`n") + "`n"

    # 在 lab6.5.circ 中替换 ROM 的 contents（使用正则匹配该 ROM 块并替换其中的内容）
    $orig = Get-Content (Join-Path $scriptDir $circFile) -Raw
    $pattern = '(?s)(<comp lib="4" loc="\(360,400\)" name="ROM">.*?<a name="contents">)(.*?)(</a>)'
    $new = [regex]::Replace($orig, $pattern, { param($m) $m.Groups[1].Value + $newContents + $m.Groups[3].Value })
    $testCircFile = Join-Path $scriptDir ".autotest.$PID.$($file.BaseName).circ"
    Set-Content -Path $testCircFile -Value $new -Encoding UTF8

    # 运行 Logisim-ITA.jar，使用文件重定向避免管道缓冲阻塞；超时 100 秒
    $stdoutFile = Join-Path $scriptDir ".autotest.$PID.$($file.BaseName).stdout.txt"
    $stderrFile = Join-Path $scriptDir ".autotest.$PID.$($file.BaseName).stderr.txt"

    $proc = Start-Process -FilePath 'java' `
        -ArgumentList @('-jar', $jarPath, $testCircFile, '-tty', 'table') `
        -WorkingDirectory $scriptDir `
        -NoNewWindow `
        -PassThru `
        -RedirectStandardOutput $stdoutFile `
        -RedirectStandardError $stderrFile

    $finished = $true
    try {
        Wait-Process -Id $proc.Id -Timeout 100 -ErrorAction Stop
    } catch {
        $finished = $false
    }

    if (-not $finished) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Add-Content -Path $resultPath -Value "Testing $($file.Name) Timeout"
        Remove-Item $testCircFile, $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
        continue
    }

    $stdout_content = ''
    $stderr_content = ''
    if (Test-Path $stdoutFile) { $stdout_content = Get-Content $stdoutFile -Raw }
    if (Test-Path $stderrFile) { $stderr_content = Get-Content $stderrFile -Raw }
    
    Add-Content -Path $resultPath -Value "$($file.Name) :"
    
    # 优先取 stdout 的有效表格行（表格行中包含制表符），过滤掉垃圾内容
    $lines = $stdout_content -split "`r?`n" | Where-Object { $_ -and $_ -match '\t' }
    
    if ($lines.Count -gt 0) {
        $last_line = $lines | Select-Object -Last 1
        Add-Content -Path $resultPath -Value $last_line
    } else {
        # 如果 stdout 没有有效的表格行，则标记为失败
        Add-Content -Path $resultPath -Value "Testing $($file.Name) Failed"
    }
    Remove-Item $testCircFile, $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $scriptDir ".autotest.*") -ErrorAction SilentlyContinue  # 删除所有.autotest 相关的临时文件
}
