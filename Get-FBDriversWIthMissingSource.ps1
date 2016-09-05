[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$True)]
    [string]$SiteCode = "LAB",
    [Parameter(Mandatory=$True)]
    [string]$SiteServer = "localhost",
    [string]$HTMLReport = "UnusedDrivers.html"
)

Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -Verbose:$false
$StartingDriveLocation = $pwd.Drive.Name

Set-Location $startingDriveLocation`:  #this is for debug reasons.
Start-Transcript -Path "Get-FBInactiveDrivers.log" -Append -Force -WhatIf:$false
Set-Location $SiteCode`:

Class MyDriver {
    [string] $Name
    [string] $ID
    [string] $InfFile
    [string] $Version
    [string[]] $Categories
    [string[]] $Packages
    [string] $SourcePath
}

$DriversWithMissingSource = @();
Get-CMDriver | ForEach-Object {
    $myTempDriver = [MyDriver]::new()    
    $myTempDriver.ID = $PSItem.CI_ID
    $myTempDriver.Name = $PSItem.LocalizedDisplayName
    $myTempDriver.InfFile = $psitem.ContentSourcePath + "\" + $psitem.DriverINFFile
    $myTempDriver.Version = $PSItem.DriverVersion
    $myTempDriver.SourcePath = $PSItem.ContentSourcePath
    Set-Location $StartingDriveLocation`:
    if(-not (Test-Path "$($myTempDriver.InfFile)"))
    {
        Write-Verbose "Driver $($myTempDriver.Name) is missing source file"
        Write-Verbose "`t$($myTempDriver.InfFile)"
        $DriversWithMissingSource += $myTempDriver
    }
}

#delete the drivers
$DriversWithMissingSource.ID| ForEach-Object {
    if ($pscmdlet.ShouldProcess($PSItem, 'Delete driver')) { #whatif?
        Remove-CMDriver -Id $PSItem -Force -Verbose
    }
}

if($HTMLReport)
{
    <#$a = "<style>"
    $a = $a + "BODY{background-color:white;}"
    $a = $a + "TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;text-align: left;}"
    $a = $a + "TH{border-width: 1px;padding: 1px;border-style: solid;border-color: black;text-align: left;}"
    $a = $a + "TD{border-width: 1px;padding: 1px;border-style: solid;border-color: black;}"
    $a = $a + "</style>"
    $RowExample = "<tr><td>Intel(R) Smart Sound Technology (Intel(R) SST) OED</td><td>16787493</td><td>IntcOED.inf</td><td>8.20.0.877</td><td>System.String[]</td><td>System.String[]</td></tr>"
    #>
    #Unused Drivers
    $html = 
@"
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
    <style>BODY{background-color:white;}TABLE{border-width: 1px;border-style: solid;border-color: black;border-collapse: collapse;text-align: left;}TH{border-width: 1px;padding: 1px;border-style: solid;border-color: black;text-align: left;}TD{border-width: 1px;padding: 1px;border-style: solid;border-color: black;}</style>
    </head><body>
    <H2>Unused Driver Information</H2>
    <table>
    <colgroup><col/><col/><col/><col/><col/><col/><col/></colgroup>
    <tr><th>Name</th><th>ID</th><th>InfFile</th><th>Version</th><th>Source Path</th></tr>
"@
    $DriversWithMissingSource = $DriversWithMissingSource | Sort-Object -Property Name
    $DriversWithMissingSource | ForEach-Object {
        $HTML = "$HTML<tr><td>$($PSItem.Name)</td><td>$($PSItem.ID)</td><td>$($PSItem.InfFile)</td><td>$($PSItem.Version)</td><td>$($PSItem.SourcePath)</td></tr>"
    }
    $html = "$HTML </table>"
    $html = "$HTML </body></html>"

    $HTML | Out-File $HTMLReport -WhatIf:$false
}

