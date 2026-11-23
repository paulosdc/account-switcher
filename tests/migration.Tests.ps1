. (Join-Path $PSScriptRoot '_fake-accounts.ps1')   # only for $ScriptsDir
$realProfile = $env:USERPROFILE

$oldJson = @'
{
  "principal": "a",
  "padrao": "b",
  "publicar": "a",
  "atalhoExplorer": "cc",
  "chrome": "a",
  "avisoUso": 70,
  "extra": "keep-me",
  "contas": {
    "a": { "email": "a@x", "pasta": "~/.claude", "rc": true, "note": "keep-too" },
    "b": { "email": "b@x", "pasta": "C:\\Users\\x\\.claude-contas\\b", "rc": false }
  }
}
'@

# Builds a fake profile that holds only the OLD install (~/.claude-contas) and dot-sources common.ps1
# pointing at it. Use with dot-source: . New-LegacyProfile $root
# Afterwards $LegacyBaseDir, $BaseDir and $MasterDir (from common.ps1) point inside $root.
function New-LegacyProfile([string]$root) {
    New-Item -ItemType Directory -Force (Join-Path $root '.claude') | Out-Null
    $env:USERPROFILE = $root
    . (Join-Path $ScriptsDir 'common.ps1')
}

# Fills the old folder: the old config (contas.json), old scripts, an account with a login, a user file.
function Initialize-LegacyFolder([string]$legacy, [string]$json) {
    foreach ($d in 'rc', 'explorer', 'b', 'backups') { New-Item -ItemType Directory -Force (Join-Path $legacy $d) | Out-Null }
    [IO.File]::WriteAllText((Join-Path $legacy 'contas.json'), $json)
    foreach ($rel in 'comum.ps1', 'instalar.ps1', 'setup-contas.ps1', 'desfazer-contas.ps1', 'abrir-conta.ps1',
                     'contas.exemplo.json', 'modelo-CLAUDE.md', 'explorer\claude-aqui.cmd', 'explorer\claude-aqui.ps1',
                     'rc\ligado.json', 'rc\desligado.json', 'cc.ps1.desativado') {
        [IO.File]::WriteAllText((Join-Path $legacy $rel), 'old script')
    }
    [IO.File]::WriteAllText((Join-Path $legacy 'my-notes.txt'), 'user file')
    [IO.File]::WriteAllText((Join-Path $legacy 'rc\mine.json'), 'user rc file')
    [IO.File]::WriteAllBytes((Join-Path $legacy 'b\.credentials.json'), [byte[]](0, 255, 254, 1, 128, 10, 13, 65))
    New-Item -ItemType Directory -Force (Join-Path $legacy 'b\projects') | Out-Null
    [IO.File]::WriteAllText((Join-Path $legacy 'b\projects\session.jsonl'), 'session data')
}

Describe 'Convert-LegacyAccountsJson' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'converts the old keys, keeps rc boolean and keeps unknown keys' {
        . New-LegacyProfile (Join-Path $TestDrive 'c1')
        $n = Convert-LegacyAccountsJson $oldJson | ConvertFrom-Json
        $n.main | Should Be 'a'
        $n.default | Should Be 'b'
        $n.publish | Should Be 'a'
        $n.explorerShortcut | Should Be 'cc'
        $n.chrome | Should Be 'a'
        $n.usageWarning | Should Be 70
        $n.extra | Should Be 'keep-me'
        $names = @($n.PSObject.Properties.Name)
        foreach ($old in 'principal', 'padrao', 'publicar', 'atalhoExplorer', 'avisoUso', 'contas') { ($names -contains $old) | Should Be $false }
        $n.accounts.a.email | Should Be 'a@x'
        $n.accounts.a.dir | Should Be '~/.claude'
        $n.accounts.a.rc | Should Be $true
        ($n.accounts.a.rc -is [bool]) | Should Be $true
        ($n.accounts.b.rc -is [bool]) | Should Be $true
        $n.accounts.b.rc | Should Be $false
        $n.accounts.a.note | Should Be 'keep-too'
        (@($n.accounts.a.PSObject.Properties.Name) -contains 'pasta') | Should Be $false
    }

    It 'rewrites a dir that mentions .claude-contas to .claude-accounts' {
        . New-LegacyProfile (Join-Path $TestDrive 'c2')
        $n = Convert-LegacyAccountsJson $oldJson | ConvertFrom-Json
        $n.accounts.b.dir | Should Be 'C:\Users\x\.claude-accounts\b'
        $n.accounts.a.dir | Should Be '~/.claude'
    }
}

Describe 'Test-LegacyInstall' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'is false when there is nothing to migrate' {
        . New-LegacyProfile (Join-Path $TestDrive 't1')
        Test-LegacyInstall | Should Be $false
    }

    It 'is true only when the old folder exists and the new one does not' {
        . New-LegacyProfile (Join-Path $TestDrive 't2')
        New-Item -ItemType Directory -Force $LegacyBaseDir | Out-Null
        Test-LegacyInstall | Should Be $true
        New-Item -ItemType Directory -Force $BaseDir | Out-Null
        Test-LegacyInstall | Should Be $false
    }

    It 'is true when the new folder was renamed but still has contas.json and no accounts.json' {
        . New-LegacyProfile (Join-Path $TestDrive 't3')
        New-Item -ItemType Directory -Force $BaseDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $BaseDir 'contas.json'), $oldJson)
        Test-LegacyInstall | Should Be $true
        [IO.File]::WriteAllText((Join-Path $BaseDir 'accounts.json'), '{}')
        Test-LegacyInstall | Should Be $false
    }
}

Describe 'Move-LegacyInstall' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'renames the folder; account folders and their files survive byte for byte' {
        . New-LegacyProfile (Join-Path $TestDrive 'm1')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $msgs = @(Move-LegacyInstall)
        # the old name is no longer a real folder (on Windows it is a junction to the new one)
        ((Test-Path -LiteralPath $LegacyBaseDir) -and -not (Test-LegacyJunction)) | Should Be $false
        (Test-Path -LiteralPath $BaseDir) | Should Be $true
        ([IO.File]::ReadAllBytes((Join-Path $BaseDir 'b\.credentials.json')) -join ',') | Should Be '0,255,254,1,128,10,13,65'
        [IO.File]::ReadAllText((Join-Path $BaseDir 'b\projects\session.jsonl')) | Should Be 'session data'
        ($msgs -join "`n") | Should Match 'renamed'
    }

    It 'writes accounts.json and keeps the old file in backups' {
        . New-LegacyProfile (Join-Path $TestDrive 'm2')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $null = Move-LegacyInstall
        $n = Get-Content -LiteralPath (Join-Path $BaseDir 'accounts.json') -Raw | ConvertFrom-Json
        $n.main | Should Be 'a'
        $n.accounts.b.dir | Should Be 'C:\Users\x\.claude-accounts\b'
        (Test-Path -LiteralPath (Join-Path $BaseDir 'contas.json')) | Should Be $false
        $keep = Join-Path $BaseDir 'backups\contas.json.before-migration'
        [IO.File]::ReadAllText($keep) | Should Be $oldJson
        # the new file is readable by the library
        (Get-Accounts).Main | Should Be 'a'
    }

    It 'removes the old script files but leaves unknown user files' {
        . New-LegacyProfile (Join-Path $TestDrive 'm3')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $null = Move-LegacyInstall
        # instalar.ps1, setup-contas.ps1, desfazer-contas.ps1 and abrir-conta.ps1 are not removed: the install
        # overwrites them with shims that forward to the new scripts
        foreach ($rel in 'comum.ps1', 'contas.exemplo.json', 'modelo-CLAUDE.md', 'explorer\claude-aqui.cmd', 'explorer\claude-aqui.ps1',
                         'rc\ligado.json', 'rc\desligado.json', 'cc.ps1.desativado') {
            (Test-Path -LiteralPath (Join-Path $BaseDir $rel)) | Should Be $false
        }
        Test-LegacyInstall | Should Be $false
        [IO.File]::ReadAllText((Join-Path $BaseDir 'my-notes.txt')) | Should Be 'user file'
        [IO.File]::ReadAllText((Join-Path $BaseDir 'rc\mine.json')) | Should Be 'user rc file'
    }

    It 'renames backups\instalacao_* to install_*' {
        . New-LegacyProfile (Join-Path $TestDrive 'm4')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $b = Join-Path $LegacyBaseDir 'backups'
        New-Item -ItemType Directory -Force (Join-Path $b 'instalacao_20240101-1200'), (Join-Path $b 'other') | Out-Null
        [IO.File]::WriteAllText((Join-Path $b 'instalacao_20240101-1200\settings.json'), 'saved')
        $null = Move-LegacyInstall
        $nb = Join-Path $BaseDir 'backups'
        (Test-Path -LiteralPath (Join-Path $nb 'instalacao_20240101-1200')) | Should Be $false
        [IO.File]::ReadAllText((Join-Path $nb 'install_20240101-1200\settings.json')) | Should Be 'saved'
        (Test-Path -LiteralPath (Join-Path $nb 'other')) | Should Be $true
    }

    It 'rewrites the statusLine path in the master settings.json' {
        . New-LegacyProfile (Join-Path $TestDrive 'm5')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $f = Join-Path $MasterDir 'settings.json'
        [IO.File]::WriteAllText($f, '{"theme":"dark","statusLine":{"type":"command","command":"powershell -File C:/Users/x/.claude-contas/statusline.ps1"}}')
        $msgs = @(Move-LegacyInstall)
        $t = [IO.File]::ReadAllText($f)
        $t | Should Match ([regex]::Escape('C:/Users/x/.claude-accounts/statusline.ps1'))
        $t | Should Not Match 'claude-contas'
        ($t | ConvertFrom-Json).theme | Should Be 'dark'
        ($msgs -join "`n") | Should Match 'statusLine'
    }

    It 'leaves settings.json untouched when it is invalid JSON' {
        . New-LegacyProfile (Join-Path $TestDrive 'm6')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $f = Join-Path $MasterDir 'settings.json'
        $broken = '{"statusLine":{"command":"C:/x/.claude-contas/statusline.ps1"} "theme":'
        [IO.File]::WriteAllText($f, $broken)
        $null = Move-LegacyInstall
        [IO.File]::ReadAllText($f) | Should Be $broken
    }

    It 'renames the CLAUDE.md markers and keeps the user text' {
        . New-LegacyProfile (Join-Path $TestDrive 'm7')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $f = Join-Path $MasterDir 'CLAUDE.md'
        [IO.File]::WriteAllText($f, "# Mine`n`n<!-- account-switcher:inicio -->`nblock body`n<!-- account-switcher:fim -->`n`nend of user text`n")
        $null = Move-LegacyInstall
        $t = [IO.File]::ReadAllText($f)
        $t | Should Match ([regex]::Escape('<!-- account-switcher:begin -->'))
        $t | Should Match ([regex]::Escape('<!-- account-switcher:end -->'))
        $t | Should Not Match 'inicio|:fim'
        $t | Should Match '# Mine'
        $t | Should Match 'block body'
        $t | Should Match 'end of user text'
    }

    It 'is a no-op returning no messages when there is nothing to migrate' {
        . New-LegacyProfile (Join-Path $TestDrive 'm8')
        $msgs = @(Move-LegacyInstall)
        $msgs.Count | Should Be 0
        (Test-Path -LiteralPath $BaseDir) | Should Be $false
        (Test-Path -LiteralPath $LegacyBaseDir) | Should Be $false
    }

    It 'refuses when both folders exist, even with the old settings.json and CLAUDE.md markers present, and changes nothing' {
        . New-LegacyProfile (Join-Path $TestDrive 'm9')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        New-Item -ItemType Directory -Force $BaseDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $BaseDir 'accounts.json'), '{"main":"z","accounts":{}}')
        $settings = '{"statusLine":{"type":"command","command":"x/.claude-contas/statusline.ps1"}}'
        $claudeMd = "# mine`n<!-- account-switcher:inicio -->`nold`n<!-- account-switcher:fim -->`n"
        [IO.File]::WriteAllText((Join-Path $MasterDir 'settings.json'), $settings)
        [IO.File]::WriteAllText((Join-Path $MasterDir 'CLAUDE.md'), $claudeMd)
        # the old statusLine path and markers make Test-LegacyInstall true: that is the case the guard has to catch
        Test-LegacyInstall | Should Be $true
        Test-LegacyBothFolders | Should Be $true
        $failed = $null
        try { Move-LegacyInstall | Out-Null } catch { $failed = $_.Exception.Message }
        $failed | Should Match 'Both .* exist'
        $failed | Should Match 'nothing was changed'
        (Test-Path -LiteralPath (Join-Path $LegacyBaseDir 'contas.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $LegacyBaseDir 'comum.ps1')) | Should Be $true
        [IO.File]::ReadAllText((Join-Path $BaseDir 'accounts.json')) | Should Be '{"main":"z","accounts":{}}'
        [IO.File]::ReadAllText((Join-Path $MasterDir 'settings.json')) | Should Be $settings
        [IO.File]::ReadAllText((Join-Path $MasterDir 'CLAUDE.md')) | Should Be $claudeMd
    }

    It 'resumes a run that renamed the folder but stopped before converting' {
        . New-LegacyProfile (Join-Path $TestDrive 'm10')
        # Already renamed: contas.json and the old scripts are inside the NEW folder, no accounts.json, no old folder.
        Initialize-LegacyFolder $BaseDir $oldJson
        (Test-Path -LiteralPath $LegacyBaseDir) | Should Be $false
        $msgs = @(Move-LegacyInstall)
        ($msgs -join "`n") | Should Not Match 'renamed to'
        ($msgs -join "`n") | Should Match 'converted'
        (Get-Accounts).Main | Should Be 'a'
        [IO.File]::ReadAllText((Join-Path $BaseDir 'backups\contas.json.before-migration')) | Should Be $oldJson
        (Test-Path -LiteralPath (Join-Path $BaseDir 'contas.json')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $BaseDir 'comum.ps1')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $BaseDir 'rc\ligado.json')) | Should Be $false
        [IO.File]::ReadAllText((Join-Path $BaseDir 'my-notes.txt')) | Should Be 'user file'
        ([IO.File]::ReadAllBytes((Join-Path $BaseDir 'b\.credentials.json')) -join ',') | Should Be '0,255,254,1,128,10,13,65'
        Test-LegacyInstall | Should Be $false
    }
}

Describe 'Move-LegacyInstall: interrupted and broken installs' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'finishes the cleanup of a run that already wrote accounts.json' {
        . New-LegacyProfile (Join-Path $TestDrive 'r1')
        # The conversion happened, but the run stopped before the rest: old scripts, markers and statusLine remain.
        Initialize-LegacyFolder $BaseDir $oldJson
        Remove-Item -LiteralPath (Join-Path $BaseDir 'contas.json')
        [IO.File]::WriteAllText((Join-Path $BaseDir 'accounts.json'), (Convert-LegacyAccountsJson $oldJson))
        New-Item -ItemType Directory -Force (Join-Path $BaseDir 'backups\instalacao_2026-01-01_000000') | Out-Null
        [IO.File]::WriteAllText((Join-Path $MasterDir 'settings.json'), '{"statusLine":{"type":"command","command":"x/.claude-contas/statusline.ps1"}}')
        [IO.File]::WriteAllText((Join-Path $MasterDir 'CLAUDE.md'), "# mine`n<!-- account-switcher:inicio -->`nold`n<!-- account-switcher:fim -->`n")
        Test-LegacyInstall | Should Be $true
        $null = Move-LegacyInstall
        (Test-Path -LiteralPath (Join-Path $BaseDir 'comum.ps1')) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $BaseDir 'backups\install_2026-01-01_000000')) | Should Be $true
        [IO.File]::ReadAllText((Join-Path $MasterDir 'settings.json')) | Should Match '\.claude-accounts/statusline\.ps1'
        $md = [IO.File]::ReadAllText((Join-Path $MasterDir 'CLAUDE.md'))
        $md | Should Match 'account-switcher:begin'
        $md | Should Not Match 'account-switcher:inicio'
        [IO.File]::ReadAllText((Join-Path $BaseDir 'accounts.json')) | Should Be (Convert-LegacyAccountsJson $oldJson)
        Test-LegacyInstall | Should Be $false
    }

    It 'stops before changing anything when contas.json is not valid JSON' {
        . New-LegacyProfile (Join-Path $TestDrive 'r2')
        Initialize-LegacyFolder $LegacyBaseDir '{"principal":"a"'
        $failed = $null
        try { Move-LegacyInstall | Out-Null } catch { $failed = $_.Exception.Message }
        $failed | Should Match 'contas\.json is not valid JSON'
        $failed | Should Match 'Nothing was changed'
        (Test-Path -LiteralPath $LegacyBaseDir) | Should Be $true
        (Test-Path -LiteralPath $BaseDir) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $LegacyBaseDir 'comum.ps1')) | Should Be $true
    }

    It 'warns instead of staying silent when settings.json is invalid and still has the old statusLine path' {
        . New-LegacyProfile (Join-Path $TestDrive 'r3')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        [IO.File]::WriteAllText((Join-Path $MasterDir 'settings.json'), '{ not json .claude-contas/statusline.ps1')
        $msgs = (Move-LegacyInstall) -join "`n"
        $msgs | Should Match 'WARNING'
        [IO.File]::ReadAllText((Join-Path $MasterDir 'settings.json')) | Should Be '{ not json .claude-contas/statusline.ps1'
    }
}

Describe 'Move-LegacyInstall: old folder name keeps working' {
    AfterAll { $env:USERPROFILE = $realProfile }
    $onWindows = $env:OS -eq 'Windows_NT'

    It 'leaves a junction under the old name that resolves into the new folder' -Skip:(-not $onWindows) {
        . New-LegacyProfile (Join-Path $TestDrive 'j1')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        $msgs = (Move-LegacyInstall) -join "`n"
        $msgs | Should Match 'junction'
        Test-LegacyJunction | Should Be $true
        # a path saved through the old name (what installed_plugins.json holds) still reaches the file
        [IO.File]::ReadAllText((Join-Path $LegacyBaseDir 'b\projects\session.jsonl')) | Should Be 'session data'
        # and it is not seen as "both folders exist" nor as something left to migrate
        Test-LegacyBothFolders | Should Be $false
        Test-LegacyInstall | Should Be $false
    }

    It 'creates the junction also when a previous run stopped right after the rename' -Skip:(-not $onWindows) {
        . New-LegacyProfile (Join-Path $TestDrive 'j2')
        Initialize-LegacyFolder $BaseDir $oldJson
        $null = Move-LegacyInstall
        Test-LegacyJunction | Should Be $true
    }

    It 'only warns, and does not throw, when the junction cannot be created' {
        . New-LegacyProfile (Join-Path $TestDrive 'j3')
        Initialize-LegacyFolder $LegacyBaseDir $oldJson
        Mock New-Item { throw 'access denied' } -ParameterFilter { $ItemType -eq 'Junction' }
        $msgs = (Move-LegacyInstall) -join "`n"
        $msgs | Should Match 'WARNING could not create the junction'
        (Test-Path -LiteralPath (Join-Path $BaseDir 'accounts.json')) | Should Be $true
    }
}

Describe 'Get-RunningClaudeProcesses' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'lists claude processes that are not this script or one of its ancestors' {
        . New-LegacyProfile (Join-Path $TestDrive 'p1')
        Mock Get-ParentProcessIds { @(100, 200) }
        Mock Get-Process { @([pscustomobject]@{ Id = 200 }, [pscustomobject]@{ Id = 300 }) }
        $found = @(Get-RunningClaudeProcesses)
        $found.Count | Should Be 1
        $found[0].Id | Should Be 300
    }

    It 'is empty when the only claude process is an ancestor (the session that runs the installer)' {
        . New-LegacyProfile (Join-Path $TestDrive 'p2')
        Mock Get-ParentProcessIds { @(100, 200) }
        Mock Get-Process { @([pscustomobject]@{ Id = 200 }) }
        @(Get-RunningClaudeProcesses).Count | Should Be 0
    }
}

Describe 'Shims for the old script names' {
    $shims = @{ 'abrir-conta.ps1' = 'open-account.ps1'; 'setup-contas.ps1' = 'setup-accounts.ps1'
                'desfazer-contas.ps1' = 'uninstall.ps1'; 'instalar.ps1' = 'install.ps1' }
    foreach ($old in $shims.Keys) {
        It "$old forwards to $($shims[$old])" {
            $text = [IO.File]::ReadAllText((Join-Path $ScriptsDir $old))
            $text | Should Match ([regex]::Escape("'$($shims[$old])'"))
            (Test-Path -LiteralPath (Join-Path $ScriptsDir $shims[$old])) | Should Be $true
        }
    }
    It 'cc still accepts --listar and --contas' {
        $text = [IO.File]::ReadAllText((Join-Path $ScriptsDir 'cc.ps1'))
        $text | Should Match "'--listar'"
        $text | Should Match "'--contas'"
    }
    It 'install.ps1 forwards -Verificar as -Check and uninstall -ApagarPastas as -DeleteFolders' {
        [IO.File]::ReadAllText((Join-Path $ScriptsDir 'instalar.ps1')) | Should Match '-Check:\$Verificar'
        [IO.File]::ReadAllText((Join-Path $ScriptsDir 'desfazer-contas.ps1')) | Should Match '-DeleteFolders:\$ApagarPastas'
    }
}

Describe 'Get-LegacyConfigPath and Find-LegacyPathReferences' {
    AfterAll { $env:USERPROFILE = $realProfile }

    It 'finds the old config in the old folder, then in the new one, else nothing' {
        . New-LegacyProfile (Join-Path $TestDrive 'f1')
        Get-LegacyConfigPath | Should Be $null
        New-Item -ItemType Directory -Force $BaseDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $BaseDir 'contas.json'), '{}')
        Get-LegacyConfigPath | Should Be (Join-Path $BaseDir 'contas.json')
        New-Item -ItemType Directory -Force $LegacyBaseDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $LegacyBaseDir 'contas.json'), '{}')
        Get-LegacyConfigPath | Should Be (Join-Path $LegacyBaseDir 'contas.json')
    }

    It 'reports files that still mention the old folder and stays quiet otherwise' {
        . New-LegacyProfile (Join-Path $TestDrive 'f2')
        New-Item -ItemType Directory -Force (Join-Path $MasterDir 'plugins') | Out-Null
        [IO.File]::WriteAllText((Join-Path $MasterDir 'settings.json'), '{"theme":"dark"}')
        @(Find-LegacyPathReferences).Count | Should Be 0
        [IO.File]::WriteAllText((Join-Path $MasterDir 'plugins\installed_plugins.json'), '{"p":{"installPath":"C:\\Users\\x\\.claude-contas\\b\\plugins\\p"}}')
        $found = @(Find-LegacyPathReferences)
        $found.Count | Should Be 1
        $found[0] | Should Be (Join-Path $MasterDir 'plugins\installed_plugins.json')
        # the report only reads: the file is not rewritten
        [IO.File]::ReadAllText($found[0]) | Should Match 'claude-contas'
    }
}

$env:USERPROFILE = $realProfile
