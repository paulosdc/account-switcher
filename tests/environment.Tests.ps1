. (Join-Path $PSScriptRoot '_fake-accounts.ps1')
$realProfile = $env:USERPROFILE
$root = Join-Path ([IO.Path]::GetTempPath()) ("mc-env-" + [guid]::NewGuid())
. New-FakeEnvironment $root @{ main = 'a'; accounts = @{ a = @{ email = 'a@x' } } }
$env:USERPROFILE = $realProfile

Describe 'Clear-ParentSessionEnv' {
    It 'removes the inherited CLAUDE* variables and keeps CLAUDE_CONFIG_DIR' {
        $saved = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $saved[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDECODE = '1'
            $env:CLAUDE_CONFIG_DIR = 'C:\x'
            $env:ANTHROPIC_TEST_MC = 'stays'
            $removed = Clear-ParentSessionEnv
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            $env:CLAUDECODE | Should Be $null
            $env:CLAUDE_CONFIG_DIR | Should Be 'C:\x'
            $env:ANTHROPIC_TEST_MC | Should Be 'stays'
            ($removed -contains 'CLAUDE_CODE_CHILD_SESSION') | Should Be $true
        } finally {
            Remove-Item Env:ANTHROPIC_TEST_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $saved.Keys) { Set-Item "Env:$k" $saved[$k] }
        }
    }

    It 'keeps the CLAUDE* variables the user set in their own environment (User/Machine)' {
        $saved = @{}
        Get-ChildItem Env: | Where-Object Name -like 'CLAUDE*' | ForEach-Object { $saved[$_.Name] = $_.Value }
        try {
            $env:CLAUDE_CODE_CHILD_SESSION = '1'
            $env:CLAUDE_CODE_GIT_BASH_PATH = 'C:\Git\bin\bash.exe'
            $removed = Clear-ParentSessionEnv @('CLAUDE_CODE_GIT_BASH_PATH')
            $env:CLAUDE_CODE_GIT_BASH_PATH | Should Be 'C:\Git\bin\bash.exe'
            $env:CLAUDE_CODE_CHILD_SESSION | Should Be $null
            ($removed -contains 'CLAUDE_CODE_GIT_BASH_PATH') | Should Be $false
        } finally {
            Remove-Item Env:CLAUDE_CODE_GIT_BASH_PATH -ErrorAction SilentlyContinue
            Remove-Item Env:ANTHROPIC_TEST_MC, Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
            foreach ($k in $saved.Keys) { Set-Item "Env:$k" $saved[$k] }
        }
    }
}

Describe 'Clear-ParentSessionEnv outside CLAUDE*' {
    It 'drops NO_COLOR and the GIT_* variables the parent session sets, so the new window opens with color' {
        $names = 'NO_COLOR', 'GIT_TERMINAL_PROMPT', 'GIT_EDITOR', 'GIT_ASKPASS'
        $saved = @{}
        foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n, 'Process') }
        try {
            $cc = $env:CLAUDECODE
            $env:CLAUDECODE = '1'
            foreach ($n in $names) { Set-Item "Env:$n" '1' }
            $dropped = Clear-ParentSessionEnv @()
            foreach ($n in $names) {
                [Environment]::GetEnvironmentVariable($n, 'Process') | Should Be $null
                ($dropped -contains $n) | Should Be $true
            }
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n], 'Process') }
            [Environment]::SetEnvironmentVariable('CLAUDECODE', $cc, 'Process')
        }
    }

    It 'drops an inherited empty GIT_ASKPASS without an error' {
        $common = Join-Path $PSScriptRoot '..\plugins\account-switcher\skills\account-switcher\scripts\common.ps1'
        $psi = New-Object Diagnostics.ProcessStartInfo 'powershell.exe'
        $psi.Arguments = "-NoProfile -Command `". '$common'; `$null = Clear-ParentSessionEnv @(); " +
            "if (Test-Path Env:GIT_ASKPASS) { 'stayed' } else { 'gone' }`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['GIT_ASKPASS'] = ''
        $psi.EnvironmentVariables['CLAUDECODE'] = '1'
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $err = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        $out.Trim() | Should Be 'gone'
        $err | Should BeNullOrEmpty
    }

    It 'outside a Claude session, keeps NO_COLOR (cc typed in the user own shell)' {
        $antes, $cc = $env:NO_COLOR, $env:CLAUDECODE
        try {
            Remove-Item Env:CLAUDECODE -ErrorAction SilentlyContinue
            $env:NO_COLOR = '1'
            $null = Clear-ParentSessionEnv @()
            $env:NO_COLOR | Should Be '1'
        } finally {
            [Environment]::SetEnvironmentVariable('NO_COLOR', $antes, 'Process')
            [Environment]::SetEnvironmentVariable('CLAUDECODE', $cc, 'Process')
        }
    }

    It 'keeps NO_COLOR when the user set it in their own environment (User/Machine)' {
        $antes = $env:NO_COLOR
        try {
            $env:NO_COLOR = '1'
            $dropped = Clear-ParentSessionEnv @('NO_COLOR')
            $env:NO_COLOR | Should Be '1'
            ($dropped -contains 'NO_COLOR') | Should Be $false
        } finally { [Environment]::SetEnvironmentVariable('NO_COLOR', $antes, 'Process') }
    }
}

Describe 'Repair-SessionTemp' {
    It 'replaces TMP and TEMP that point to the Windows folder with the user temp' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\Windows\TEMP'
            $env:TEMP = 'c:\windows\temp\'
            $replaced = Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            ($replaced -join ',') | Should Be 'TMP,TEMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'fills in the one that is empty and keeps the one that points elsewhere' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            Remove-Item Env:TMP -ErrorAction SilentlyContinue
            $env:TEMP = 'D:\my-temp'
            $replaced = Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp'
            $env:TMP | Should Be 'C:\Users\x\AppData\Local\Temp'
            $env:TEMP | Should Be 'D:\my-temp'
            ($replaced -join ',') | Should Be 'TMP'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }

    It 'does not confuse a folder that shares the Windows prefix' {
        $tmp, $temp = $env:TMP, $env:TEMP
        try {
            $env:TMP = 'C:\WindowsApps\temp'
            $env:TEMP = 'C:\WindowsApps\temp'
            @(Repair-SessionTemp 'C:\Windows' 'C:\Users\x\AppData\Local\Temp').Count | Should Be 0
            $env:TMP | Should Be 'C:\WindowsApps\temp'
        } finally { $env:TMP, $env:TEMP = $tmp, $temp }
    }
}

Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
