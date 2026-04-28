#Requires -Version 5.1

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoDir    = $PSScriptRoot
$VenvDir    = Join-Path $RepoDir '.venv'
$ActivatePs = Join-Path $VenvDir 'Scripts\Activate.ps1'
$PipExe     = Join-Path $VenvDir 'Scripts\pip.exe'
$PyVenvExe  = Join-Path $VenvDir 'Scripts\python.exe'

$UseVllm        = $args -contains '--use-vllm'
$PassthroughArgs = @($args | Where-Object { $_ -ne '--use-vllm' })

$vllmLabel = if ($UseVllm) { " [vLLM モード]" } else { "" }

Write-Host ""
Write-Host "============================================================"
Write-Host "  sarashina2.2-tts$vllmLabel"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Step 1: Python 確認
# ============================================================
Write-Host "[Step 1/5] Python を確認中..."

$PythonExe      = $null
$PythonBaseArgs = @()

try {
    $output = & py '-3.10' '--version' 2>&1
    if ($LASTEXITCODE -eq 0) {
        $PythonExe      = 'py'
        $PythonBaseArgs = @('-3.10')
        Write-Host "  $output"
    }
} catch {}

if (-not $PythonExe) {
    try {
        $output = & python '--version' 2>&1
        if ($LASTEXITCODE -eq 0) {
            $PythonExe      = 'python'
            $PythonBaseArgs = @()
            Write-Host "  $output"
            Write-Host "  注意: Python 3.10 以上が必要です（推奨: 3.10）"
        }
    } catch {}
}

if (-not $PythonExe) {
    Write-Host ""
    Write-Host "[ERROR] Python が見つかりません。Python 3.10 以上をインストールしてください:"
    Write-Host "        https://www.python.org/downloads/"
    Write-Host ""
    Read-Host "続行するには Enter キーを押してください"
    exit 1
}
Write-Host ""

# ============================================================
# Step 2: Git 確認（silentcipher が git 依存パッケージのため必須）
# ============================================================
Write-Host "[Step 2/5] Git を確認中..."

try {
    $gitVer = & git '--version' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  $gitVer"
    } else {
        throw
    }
} catch {
    Write-Host ""
    Write-Host "[ERROR] Git が見つかりません。Git をインストールしてください:"
    Write-Host "        https://git-scm.com/downloads"
    Write-Host "        （依存パッケージ silentcipher のインストールに必要です）"
    Write-Host ""
    Read-Host "続行するには Enter キーを押してください"
    exit 1
}
Write-Host ""

# ============================================================
# Step 3: 仮想環境
# ============================================================
Write-Host "[Step 3/5] 仮想環境を確認中..."

if (-not (Test-Path $ActivatePs)) {
    Write-Host "  仮想環境を作成中: $VenvDir"
    & $PythonExe @PythonBaseArgs '-m' 'venv' $VenvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] 仮想環境の作成に失敗しました。"
        Read-Host "続行するには Enter キーを押してください"
        exit 1
    }
    Write-Host "  作成完了。"
} else {
    Write-Host "  既存の仮想環境を使用: $VenvDir"
}

& $PyVenvExe '-m' 'pip' 'install' '--upgrade' 'pip' '--quiet'
Write-Host ""

# ============================================================
# Step 4: PyTorch (CUDA 12.8)
# ============================================================
Write-Host "[Step 4/5] PyTorch を確認中..."

$torchVer = & $PyVenvExe '-c' 'import torch; print(torch.__version__)' 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  PyTorch $torchVer は既にインストール済みです。スキップします。"
} else {
    Write-Host "  CUDA 12.x 対応 GPU 用の PyTorch をインストールします。"
    Write-Host "  異なる CUDA バージョンや CPU 環境の場合は手動インストールしてください:"
    Write-Host "  https://pytorch.org/get-started/locally/"
    Write-Host ""
    & $PipExe install torch torchaudio --index-url https://download.pytorch.org/whl/cu128
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] PyTorch のインストールに失敗しました。"
        Write-Host "        ネットワーク環境や CUDA バージョンを確認してください。"
        Read-Host "続行するには Enter キーを押してください"
        exit 1
    }
}
Write-Host ""

# ============================================================
# Step 5: パッケージインストール (pyproject.toml)
# ============================================================
Write-Host "[Step 5/5] 依存パッケージを確認中..."

$pyprojectFile = Join-Path $RepoDir 'pyproject.toml'
$hashFile      = Join-Path $VenvDir '.req_hash'
$hashSuffix    = if ($UseVllm) { ':vllm' } else { ':base' }

$reqHash    = (Get-FileHash $pyprojectFile -Algorithm MD5).Hash + $hashSuffix
$storedHash = if (Test-Path $hashFile) { (Get-Content $hashFile -Raw).Trim() } else { '' }

if ($reqHash -eq $storedHash) {
    Write-Host "  依存パッケージは最新です。スキップします。"
} else {
    Set-Location $RepoDir

    if ($UseVllm) {
        Write-Host "  vLLM 対応パッケージをインストールします (pip install -e .[vllm])..."
        & $PipExe install -e '.[vllm]' --extra-index-url https://download.pytorch.org/whl/cu128
    } else {
        Write-Host "  パッケージをインストールします (pip install -e .)..."
        & $PipExe install -e '.' --extra-index-url https://download.pytorch.org/whl/cu128
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[WARNING] 一部パッケージのインストールに失敗した可能性があります。"
        Write-Host "          エラーログを確認してください。"
    } else {
        [System.IO.File]::WriteAllText($hashFile, $reqHash)
    }
}
Write-Host ""

# ============================================================
# アプリ起動
# ============================================================
Write-Host "============================================================"
Write-Host "  sarashina2.2-tts$vllmLabel"
Write-Host "  URL  : http://127.0.0.1:7860"
Write-Host "  終了 : Ctrl+C"
Write-Host "============================================================"
Write-Host ""

Set-Location $RepoDir
. $ActivatePs

Start-Job -ScriptBlock {
    $tcp = [System.Net.Sockets.TcpClient]::new()
    while ($true) {
        try { $tcp.Connect('127.0.0.1', 7860); break } catch { Start-Sleep -Milliseconds 500 }
    }
    $tcp.Close()
    Start-Process 'http://127.0.0.1:7860'
} | Out-Null

if ($UseVllm) {
    python server/gradio_app.py --use-vllm @PassthroughArgs
} else {
    python server/gradio_app.py @PassthroughArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERROR] アプリの起動に失敗しました。"
    Write-Host ""
    Read-Host "続行するには Enter キーを押してください"
}
