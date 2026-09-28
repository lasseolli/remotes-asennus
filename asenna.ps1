# Etälaitteen käyttöönotto (Windows 10/11): asetushaku (lasseolli/remotes) + MeshCentral-agentti + Zabbix-raportointi.
#
#   Järjestelmänvalvojan PowerShell:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/asenna.ps1))) kallio
#
# Skripti kysyy asennusavaimen (tai lukee sen muuttujasta REMOTES_AVAIN). Avaimella avataan paketti.enc, jossa on
# yksityisen asetusrepon vain luku -avain ja ryhmien salaisuusavaimet; kone saa vain oman ryhmänsä avaimen.
# Varsinaiset asetukset tulevat yksityisestä reposta, jota kone hakee jatkossa itse tunnin välein ja verkon noustessa.
param([string]$Ryhma)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Paketti = 'https://raw.githubusercontent.com/lasseolli/remotes-asennus/main/paketti.enc'
$Repo = 'git@github.com:lasseolli/remotes.git'
$Etc = 'C:\ProgramData\Remotes'

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Aja järjestelmänvalvojan PowerShellissä' }

function Avaa-Salattu([string]$b64, [string]$salasana) {
    # openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -a -A
    $raw = [Convert]::FromBase64String($b64.Trim())
    if ([Text.Encoding]::ASCII.GetString($raw, 0, 8) -ne 'Salted__') { throw 'Tuntematon salausmuoto' }
    $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes -ArgumentList ([Text.Encoding]::UTF8.GetBytes($salasana)), ([byte[]]$raw[8..15]), 600000, ([Security.Cryptography.HashAlgorithmName]::SHA256)
    $kv = $kdf.GetBytes(48)
    $aes = [Security.Cryptography.Aes]::Create(); $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
    $aes.Key = [byte[]]$kv[0..31]; $aes.IV = [byte[]]$kv[32..47]
    [Text.Encoding]::UTF8.GetString($aes.CreateDecryptor().TransformFinalBlock($raw, 16, $raw.Length - 16))
}
# Omistajaksi SYSTEM: Windowsin OpenSSH hylkää avaimen, jonka omistaja on eri käyttäjä kuin haun ajava SYSTEM
function Vain-Yllapito($polku) { icacls $polku /setowner '*S-1-5-18' | Out-Null; icacls $polku /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' | Out-Null }

$avain = $env:REMOTES_AVAIN
if (-not $avain) {
    $s = Read-Host 'Asennusavain' -AsSecureString
    $avain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}
try { $p = Avaa-Salattu (Invoke-RestMethod $Paketti -UseBasicParsing) $avain.Trim() | ConvertFrom-Json }
catch { throw 'Väärä asennusavain tai paketti ei latautunut' }
$ryhmat = @($p.avaimet.PSObject.Properties.Name | Sort-Object)
if (-not $Ryhma -or $Ryhma -notin $ryhmat) { throw "Anna ryhmä: $($ryhmat -join ', ')" }

Write-Host "== Käyttöönotto: $env:COMPUTERNAME, ryhmä $Ryhma"
if (-not (Test-Path $Etc)) { New-Item $Etc -ItemType Directory | Out-Null }
icacls $Etc /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(RX)' | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText("$Etc\deploy-key", ($p.deploy_key -replace "`r", ''), $utf8); Vain-Yllapito "$Etc\deploy-key"
[IO.File]::WriteAllText("$Etc\avain", $p.avaimet.$Ryhma, $utf8); Vain-Yllapito "$Etc\avain"
[IO.File]::WriteAllText("$Etc\ryhma", "$Ryhma`n", $utf8)
Remove-Variable p, avain
# GitHubin SSH-palvelinavaimet (api.github.com/meta)
[IO.File]::WriteAllText("$Etc\known_hosts", @(
    'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl',
    'github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg='
) -join "`n", $utf8)

if (-not (Test-Path 'C:\Windows\System32\OpenSSH\ssh.exe')) {
    Write-Host '== OpenSSH-asiakas'
    Add-WindowsCapability -Online -Name 'OpenSSH.Client~~~~0.0.1.0' | Out-Null
}
if (-not (Test-Path "$Etc\mingit\cmd\git.exe")) {
    Write-Host '== Git (MinGit, git-for-windows)'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing
    $a = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d.]+-64-bit\.zip$' } | Select-Object -First 1
    $zip = "$env:TEMP\mingit.zip"
    Invoke-WebRequest $a.browser_download_url -OutFile $zip -UseBasicParsing
    if ($a.digest -and ('sha256:' + (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()) -ne $a.digest) { throw "MinGitin tarkiste ei täsmää ($($a.name))" }
    Expand-Archive $zip "$Etc\mingit" -Force; Remove-Item $zip
}
$git = "$Etc\mingit\cmd\git.exe"
$env:GIT_SSH_COMMAND = 'C:/Windows/System32/OpenSSH/ssh.exe -i C:/ProgramData/Remotes/deploy-key -o IdentitiesOnly=yes -o UserKnownHostsFile=C:/ProgramData/Remotes/known_hosts -o StrictHostKeyChecking=yes -o BatchMode=yes'
if (-not (Test-Path "$Etc\repo\.git")) {
    Write-Host '== Asetusrepo'
    if (Test-Path "$Etc\repo") { Remove-Item "$Etc\repo" -Recurse -Force }
    & $git -c safe.directory=* clone -q --depth 1 $Repo "$Etc\repo"
    if ($LASTEXITCODE) { throw 'Asetusrepon haku epäonnistui' }
}
Write-Host '== Ensimmäinen ajo (jatkossa ajastettu tehtävä \Remotes\Haku)'
Copy-Item "$Etc\repo\windows\remotes-pull.ps1" "$Etc\remotes-pull.ps1" -Force
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$Etc\remotes-pull.ps1"
$rc = $LASTEXITCODE
Write-Host "== Valmis (tulos $rc, 0 = onnistui). Tila: $Etc\tila.json, loki: $Etc\viimeisin.log"
$global:LASTEXITCODE = $rc   # ei exit: skriptilohko ajetaan käyttäjän istunnossa, exit sulkisi ikkunan
