<#
.SYNOPSIS
    This script should be run on as needed basis.
.DESCRIPTION
    This script is used to identIfy and then delete drivers with missing source file(s).  
    
.PARAMETER SiteCode
    The site code of your ConfigMgr site.  i.e. PS1
.PARAMETER SiteServer
    The hostname of a site server in your ConfigMgr site.
.PARAMETER HTMLReport
    The filename of a HTML report that shows what drivers are not in use.  This defaults to "UnusedDrivers.html"
.EXAMPLE
    Discover what drivers are missing source files but do not delete them. (WhatIf)
    .\Remove-FBDriversWIthMissingSource.ps1 -SiteCode LAB -SiteServer localhost -WhatIf -Verbose
    Delete drivers with missing source files.
    .\Remove-FBDriversWIthMissingSource.ps1 -SiteCode LAB -SiteServer localhost -Verbose
    Delete drivers with missing source files and create a html report named "MyUnusedDrivers.html".
    .\Remove-FBDriversWIthMissingSource.ps1 -SiteCode LAB -SiteServer localhost -Verbose -HTMLReport "MyUnusedDrivers.html"
.NOTES
    Author:    Fred Bainbridge
    Created:   2016-09-04
    
    To Do:     
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$True)]
    [string]$SiteCode = "LAB",
    [Parameter(Mandatory=$True)]
    [string]$SiteServer = "localhost",
    [string]$HTMLReport = "DriversWithMissingSource.html"
)

Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -Verbose:$false
$StartingDriveLocation = $pwd.Drive.Name

Set-Location $startingDriveLocation`:  #this is for debug reasons.
Start-Transcript -Path "Remove-FBInactiveDrivers.log" -Append -Force -WhatIf:$false
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
        #get category information about driver$tmpIds = $PSItem.CategoryInstance_UniqueIDs
        $tmpCategories = @();
        $tmpCategoriesNames = @();
        $tmpIds = $PSItem.CategoryInstance_UniqueIDs
        if($tmpIds) {
            $tmpIds | %{($_.ToString()).substring(17)} | ForEach-Object { 
                $tmpCategories += $PSItem
                $tmpCategoriesNames += (Get-CMCategory -Id "DriverCategories:$PSItem").LocalizedCategoryInstanceName
            }       
        }
        $myTempDriver.Categories = $tmpCategoriesNames
    }
    $tmpPackages = @();
    $tmpPackagesNames = @();
    Get-WmiObject -Query "select PackageID,Name from sms_drivercontainer where ci_id = '$($myTempDriver.ID)'" -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer| foreach-Object {
            $tmpPackages += $PSItem.Name
    }
    $myTempDriver.Packages = $tmpPackages
    
}

#delete the drivers
Set-Location $SiteCode`:
$DriversWithMissingSource.ID| ForEach-Object { 
    if ($pscmdlet.ShouldProcess($PSItem, 'Delete driver')) { #whatif?
        Remove-CMDriver -Id $PSItem -Force -Verbose
    }
}
Set-Location $StartingDriveLocation`:

if($HTMLReport)
{
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
    <tr><th>Name</th><th>ID</th><th>InfFile</th><th>Version</th><th>Source Path</th><th>Packages</th><th>Categories</th></tr>
"@
    $DriversWithMissingSource = $DriversWithMissingSource | Sort-Object -Property Name
    $DriversWithMissingSource | ForEach-Object {
        $tempPackages = $null
        $tempCategories = $null
        $PSItem.Packages | ForEach-Object {
            $tempPackages = "$tempPackages, $PSItem"           
            $tempPackages = $tempPackages.trim(", ")
        }
        $PSItem.Categories | ForEach-Object {
            $tempCategories = "$tempCategories, $PSItem"
        }
        if($tmpCategories)
        {
            $tempCategories = $tempCategories.Trim(", ")
        }
        $HTML = "$HTML<tr><td>$($PSItem.Name)</td><td>$($PSItem.ID)</td><td>$($PSItem.InfFile)</td><td>$($PSItem.Version)</td><td>$($PSItem.SourcePath)</td><td>$tempPackages</td><td>$tempCategories</td></tr>"
    }
    $html = "$HTML </table>"
    $html = "$HTML </body></html>"

    $HTML | Out-File $HTMLReport -WhatIf:$false
}