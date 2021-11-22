
function Inform($s)
{
    Write-Host $s
}

function Warn($s)
{
    Write-Host $s -ForegroundColor Yellow
}

function Complain($s)
{
    Write-Host $s -ForegroundColor Red
}

function ReadCredentialFile
{
    param(
        [string]$pathCredentialFile
    )

    if (!$pathCredentialFile) {
        Inform "ReadCredentialFile.ps1 pathCredentialFile"
        return
    }#if

    if (!(Test-Path $pathCredentialFile)) {
        Complain "Cannot find [$pathCredentialFile]."
        return
    }#if

    $itemPasswordFile = Get-Item $pathCredentialFile
    $pathCredentialFile = $itemPasswordFile.FullName
    $sCredentialFileName = $itemPasswordFile.BaseName
    $sUser = $sCredentialFileName
    $sPassword = Get-Content $pathCredentialFile
    $secPassword = $sPassword | ConvertTo-SecureString
    $credential = New-Object System.Management.Automation.PSCredential($sUser, $secPassword)

    return $credential
}
function WriteCredentialFile
{
    param(
        [pscredential]$credential
    )

    if (!$credential) {
        Inform "WriteCredentialFile credential"
        return
    }#if

    $sUserName = $credential.UserName
    if ($sUserName.Contains("\")){
        Warn "Please don't user netbios-style user names."
        return
    }#if
    $sPassword = $credential.Password | ConvertFrom-SecureString
    $pathPasswordFile = "$sUserName.pass"
    New-Item -ItemType "File" $pathPasswordFile -Force
    $sPassword | Out-File $pathPasswordFile
    if ($?) {Inform "Wrote encrypted password to [$pathPasswordFile]."}
}

function VIConnect
{
    param(
        $sVIServer,
        $pathCredentialFile
    )

    $ErrorActionPreference = "SilentlyContinue"

    if (!$sVIServer) {
        Warn "Connect to VIServer sVIServer:"
        Inform "VIConnect sVIServer [pathCredentialFile]"
        Warn "Disconnect from all VIServers:"
        Inform "VIConnect -"
        return
    }#if

    if ($sVIServer -eq "-") {
        Disconnect-VIServer * -Force -Confirm:$false
        return
    }#if

    if ($pathCredentialFile) {
        if (!(Test-Path $pathCredentialFile)) {
            Complain "Cannot find [$pathCredentialFile]."
            exit
        }#if
        $credential = ReadCredentialFile $pathCredentialFile
    } else {
        $credential = Get-Credential
        if ((Read-Host "Save this credential? [y/n]") -eq "y") {
            WriteCredentialFile $credential
            if ($?) {Inform "Wrote encrypted password to [$pathCredentialFile]."}
        }#if
    }#if

    Warn "Connecting to VIServer [$sVIServer]..."
    $Env:PSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath","Machine")
    Get-Module -ListAvailable VMware* | Import-Module
    $global:connection = Connect-VIServer $sVIServer -Credential $credential
    if ($?) {
        Inform "Connected to [$sVIServer]."
        return
    } else {
        Error $Error[0]
        return 1
    }#if
}
