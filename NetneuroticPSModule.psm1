
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
        if ($Global:VIConnectCredential) {
            $credential = $Global:VIConnectCredential
        } else {
            $credential = Get-Credential
            if ((Read-Host "Save this credential? [y/n]") -eq "y") {
                WriteCredentialFile $credential
                if ($?) {Inform "Wrote encrypted password to [$pathCredentialFile]."}
            }#if
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

function GetVMIp([string]$sVMName)
{
    if (!$sVMName){
        Write-Host "Get-VMIP.ps1 sVMName"
        return
    }#if

    try {
    $vm = Get-VM $sVMName
    } catch {
        Write-Host "No connection to vSphere?"
        return
    }#try

    if ($vm.PowerState -ne "PoweredOn") {
        Start-VM $vm -Confirm:0 >$null
    }#if

    Wait-Tools -VM $vm -TimeoutSeconds 300 >$null

    $view = Get-View $vm
    $guest = $view.Guest
    $ip = $guest.IpAddress

    return $ip
}

function ilocon([string]$sRIBName)
{
    & "C:\Program Files (x86)\Hewlett Packard Enterprise\HPE iLO Integrated Remote Console\HPLOCONS.exe" -addr $sRIBName
}
function sec2s([SecureString]$sec)
{
    $s = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    return $s
}
function CreateAuthHeader([string]$sUserName,[string]$sPassword)
{
    if (!$sUserName) {
        Write-Host "CreateCrumb sUserName [sPassword]"
        return
    }#if

    if (!$sPassword) {
        $sPassword = sec2s (Read-Host "Password" -AsSecureString)
    }#if

    $sPair = $sUserName + ":" + $sPassword
    $encPair = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($sPair))
    $header = @{}
    $header.Authorization="Basic $encPair"
    return $header
}

function VMAddSerialPort([string]$sVMName,[int]$port)
{
    if (!$port){
        Write-Host "addserialport sVMName port"
        return
    }#if
    $vm = Get-VM -Name $sVMName
    if ($vm.ExtensionData.Config.Hardware.Device| Where-Object {$_.DeviceInfo.Summary -like "*telnet*$port"}) {
        return
    }#if
    $dcs = New-Object VMware.Vim.VirtualDeviceConfigSpec
    $dcs.Operation = "add"
    $dcs.Device = New-Object VMware.Vim.VirtualSerialPort
    $dcs.Device.Key = -1
    $dcs.Device.Backing = New-Object VMware.Vim.VirtualSerialPortURIBackingInfo
    $dcs.Device.Backing.Direction = "server"
    $dcs.Device.Backing.ServiceURI = "telnet://:$port"
    $dcs.Device.Connectable = New-Object VMware.Vim.VirtualDeviceConnectInfo
    $dcs.Device.Connectable.Connected = $true
    $dcs.Device.Connectable.StartConnected = $true
    $dcs.Device.YieldOnPoll = $true
    $cs = New-Object VMware.Vim.VirtualMachineConfigSpec
    $cs.DeviceChange += $dcs
    $vm.ExtensionData.ReconfigVM($cs)
    #New-AdvancedSetting -Entity $vm -Name serial0.fileName -Value "telnet://:$port" -Confirm:$false -Force:$true
    #New-AdvancedSetting -Entity $vm -Name serial0.fileType -Value "network" -Confirm:$false -Force:$true
    #New-AdvancedSetting -Entity $vm -Name serial0.present -Value TRUE -Confirm:$false -Force:$true
    #New-AdvancedSetting -Entity $vm -Name serial0.yieldOnMsrRead -Value TRUE -Confirm:$false -Force:$true
}

function VMForceEfiBoot([string]$sVMName)
{
    $vm = Get-VM -Name $sVMName
    $cs = New-Object VMware.Vim.VirtualMachineConfigSpec
    $cs.BootOptions = New-Object VMware.Vim.VirtualMachineBootOptions
    $cs.BootOptions.EnterBIOSSetup = $true
    $vm.ExtensionData.ReconfigVM($cs)
}
