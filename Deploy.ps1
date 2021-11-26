$pathModule = "C:\Program Files\WindowsPowerShell\Modules\NetneuroticPSModule"
$sModuleFileName = "NetneuroticPSModule.psm1"

if (Test-Path $sModuleFileName) {
    Copy-Item $sModuleFileName $pathModule
}#if