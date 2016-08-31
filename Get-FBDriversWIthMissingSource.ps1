[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$True)]
    [string]$SiteCode = "LAB",
    [Parameter(Mandatory=$True)]
    [string]$SiteServer = "localhost",
    [string]$HTMLReport = "UnusedDrivers.html",
    [switch]$IgnoreWarnings
)

Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -Verbose:$false
set-location c:
Start-Transcript -Path "Get-FBInactiveDrivers.log" -Append -Force -WhatIf:$false
$StartingDriveLocation = $pwd.Drive.Name
Set-Location $SiteCode`:

Get-CMDriver | ForEach-Object {
    #get the source
    
    $FileName = $psitem.ContentSourcePath + "\" + $psitem.DriverINFFile
    set-location c:
    if(Test-Path "$Filename")
    {
        Write-Host "found it"
    }
    else
    {
        write-host "did not find it"
    }
    #Set-Location $SiteCode`:
}