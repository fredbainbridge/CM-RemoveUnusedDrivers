﻿<#
.SYNOPSIS
    This script should be run on as needed basis.

.DESCRIPTION
    This script is used to identIfy and then delete unused drivers.  
    If any of these conditions are true a driver is consider "in use":
	1. The driver is in a Driver Package that is referenced by a Apply Drivers step of a task sequence.
	2. The driver is in a Driver Category that is referenced by an Auto Apply Drivers step of the task sequence.
	3. The driver is imported into existing boot media.

    "Warnings" are generated If there are apply driver steps that use all drivers. 
    In order for this to be most accurate you should first cleanup or delete and legacy task sequences.
    This will find any driver referenced in all task sequences.
    Using -WhatIf the first time you run this script is highly recommended

.PARAMETER SiteCode
    The site code of your ConfigMgr site.  i.e. PS1
.PARAMETER SiteServer
    The hostname of a site server in your ConfigMgr site.
.PARAMETER HTMLReport
    The filename of a HTML report that shows what drivers are not in use.  This defaults to "UnusedDrivers.html"
.PARAMETER IgnoreWarnings
    Switch parameter.  SpecIfy this If you want to Ignore warnings about auto apply drivers steps.

.EXAMPLE
    Discover what drivers are not in use but do not delete them. (WhatIf)
    .\Remove-FBInactiveDrivers.ps1 -SiteCode "XXX" -SiteServer "CM01.CM.LAB" -HTMLReport "DriverUsageReport.html" -IgnoreWarnings -WhatIf -Verbose

    Delete unused drivers ignore warnings for auto apply all drivers steps.
    .\Remove-FBInactiveDrivers.ps1 -SiteCode "XXX" -SiteServer "CM01.CM.LAB" -HTMLReport "DriverUsageReport.html" -IgnoreWarnings -Verbose

    Delete unused drivers with warnings when auto apply all drivers steps are found.
    .\Remove-FBInactiveDrivers.ps1 -SiteCode "XXX" -SiteServer "CM01.CM.LAB" -HTMLReport "DriverUsageReport.html" -Verbose

.NOTES
    Author:    Fred Bainbridge
    Created:   2016-08-29
    
    To Do:     
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$True)]
    [string]$SiteCode,
    [Parameter(Mandatory=$True)]
    [string]$SiteServer,
    [string]$HTMLReport = "UnusedDrivers.html",
    [switch]$IgnoreWarnings
)

Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -Verbose:$false

Start-Transcript -Path "Get-FBInactiveDrivers.log" -Append -Force -WhatIf:$false
$StartingDriveLocation = $pwd.Drive.Name
Set-Location $SiteCode`:

Function EvaluateTS {
    [CmdletBinding()]
    param(
        $TaskSequenceXML
    )
    $IDs = @();  #category or package ID
    $TaskSequenceXML | ForEach-Object {
        #If($psitem.name -ne "sequence"){Write-Verbose "Group:  $($PSItem.name)"}
        If($psitem.step){
            $psitem.step | ForEach-Object {
                If ((([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('disable="true"') -eq "-1") #ensure the step isn't disabled.
                {
                    If($psitem.type -eq 'SMS_TaskSequence_ApplyDriverPackageAction') 
                    { 
                        #Write-Verbose 'SMS_TaskSequence_ApplyDriverPackageAction'
                        $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('/install:')
                        $PackageID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + '/install:'.Length,8)
                        Write-Verbose "Driver Package: $PackageID found in step `"$($psitem.name)`" "
                        $IDs += $PackageID
                    }
                    If($psitem.type -eq 'SMS_TaskSequence_AutoApplyAction') 
                    {
                        $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('DriverCategories:')
                        If($index -ne "-1") 
                        {
                            $CategoryID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + 'DriverCategories:'.Length,36)
                            Write-Verbose "Driver Category $CategoryID found in Step - $($psitem.name)"
                            $IDs += $CategoryID
                        }
                        Else
                        {
                            Write-Verbose "This task sequence step applies drivers from all categories and is not disabled.  This makes it impossible to determine what drivers are not being used.  This should be a build and capture task sequence or something Else expected."
                            If( -not $IgnoreWarnings)
                            {
                                $response = Read-Host -Prompt "Warning! Continue? Y/N"
                                If( $response.ToUpper() -ne "Y" ) { exit }
                            }
                            Else
                            {
                                Write-Verbose "Ignoring Warning"
                            }
                        }
                    }
                } 
                Else
                {
                    Write-Verbose "Driver step $($psitem.name) is disabled, skipping"
                } #end of disabled step check
            } #end of steps
        }
        If($psitem.group)
        {
            $IDs += EvaluateTS -TaskSequenceXML $psitem.group -verbose  
        }

    }
    #write-output $CategoryIDs -verbose
    #Write-Output $packageIDs -verbose
    write-output $IDs
}

$IDs = @() #Packages or Categories
Get-CMTaskSequence | ForEach-Object {
    #([xml](Get-CMTaskSequence | select sequence).sequence)
    Write-Verbose "---------Task Sequence - $($PSItem.Name)---------"
    $sequence = [xml]$psitem.sequence
    $IDs += EvaluateTS -TaskSequenceXML $sequence.sequence -verbose 
}
$IDs = $IDs | select -Unique
$Categories = $IDs -match ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")
$Packages = $IDs -notmatch ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")
If($Categories -eq $true) {$Categories = $ID} #only one category found
Write-Verbose "All Categories in use : "
$Categories | ForEach-Object { Write-Verbose $PSItem}
Write-Verbose "All Packages in use : "
$Packages | ForEach-Object { Write-Verbose $PSItem}
#get drivers IDs used in boot images
$driversInBootMedia = @();
Write-Verbose "Looking for drivers referenced by boot images"
Get-CMBootImage | ForEach-Object {
    $bootImageName = $psitem.name
    $PSItem.ReferencedDrivers | ForEach-Object {
        $driversInBootMedia += $PSItem.id
        Write-Verbose "Found driver $($psitem.id) in boot image $bootImageName"
    }    
}


#WMI Example 
#Get-WmiObject -Query "select * from sms_driver where ci_id = '17101826'" -Namespace 'root\sms\site_arc'

#Store unused driver information in this class.
Class MyDriver {
    [string] $Name
    [string] $ID
    [string] $InfFile
    [string] $Version
    [string[]] $Categories
    [string[]] $Packages
    [string] $SourcePath
}

Class MyPackage {
    [string] $Name
    [string] $ID
}

Class MyCategory {
    [string] $Name
    [string] $ID
}

$UnusedDriverObjects = @();

Get-CMDriver | ForEach-Object {
    $myTempDriver = [MyDriver]::new()

    $InActiveCategory = $false
    $InActivePackage = $false
    $InBootMedia = $false

    $myTempDriver.ID = $PSItem.CI_ID
    $myTempDriver.Name = $PSItem.LocalizedDisplayName
    $myTempDriver.InfFile = $PSItem.DriverInfFile
    $myTempDriver.Version = $PSItem.DriverVersion
    $myTempDriver.SourcePath = $PSItem.ContentSourcePath
    

    Write-Verbose "---------$($myTempDriver.Name)---------"
    
    #is this in a used category?
    If($PSItem.CategoryInstance_UniqueIDs -ne $null)
    {
        $tmpCategories = @();
        $tmpCategoriesNames = @();
        $tmpIds = $PSItem.CategoryInstance_UniqueIDs
        $tmpIds | %{($_.ToString()).substring(17)} | ForEach-Object { 
            If($PSItem -in $Categories)
            {
                $InActiveCategory = $true 
                Write-Verbose "$($myTempDriver.Name) is in active category $PSItem"
            }
            $tmpCategories += $PSItem
            $tmpCategoriesNames += (Get-CMCategory -Id "DriverCategories:$PSItem").LocalizedCategoryInstanceName
        }       
        $myTempDriver.Categories = $tmpCategoriesNames
    }
    If(-not $InActiveCategory) {
        Write-Verbose "$($myTempDriver.Name) is not in an active category"
    }
    
    #is this in a used driver package?
    $tmpPackages = @();
    Get-WmiObject -Query "select PackageID from sms_drivercontainer where ci_id = '$($myTempDriver.ID)'" -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer| foreach-Object {
            If($PSItem.PackageID -in $Packages) 
            {
                Write-Verbose "$($myTempDriver.Name) is in active package $($PSitem.PackageID)" 
                $InActivePackage = $true
            }
            $tmpPackages += $PSItem.PackageID
    }
    $myTempDriver.Packages = $tmpPackages

    If( -not $InActivePackage)
    {
        Write-Verbose "$($myTempDriver.Name) is not in an active package " 
    }
    
    #is it in boot media?
    If($myTempDriver.ID -in $driversInBootMedia)
    {
        Write-Verbose "$($myTempDriver.Name), drive Id: $($MyTempDriver.ID) is used for boot media"
        $InBootMedia = $true
    }
    Else
    {
        Write-Verbose "$($myTempDriver.Name) is not in a boot media"
    }
    If(-not $InActiveCategory -and (-not $InActivePackage) -and (-not $InBootMedia))  #this is an unused driver.
    {
        $UnusedDriverObjects += $myTempDriver
        Write-Verbose "$($myTempDriver.Name), ID: $($MyTempDriver.ID) is unused and can be deleted."
    }
}
#$UnusedDriverObjects | select LocalizedDisplayName, DriverInfFile, DriverVersion

#evaluate If driver packages are used
#Unused Driver Packages.  This is unlikely to be super helpful.  Drivers in packages will also have categories.  
Write-Verbose "Looking for unused driver packages."
$unusedDriverPackages = @();
Get-CMDriverPackage | ForEach-Object {
    $myTempPackage = [myPackage]::new()
    If($PSItem.PackageID -in $packages ) {        
        Write-Verbose "Driver Package $($PSItem.Name) is in use"
    }
    Else
    {
        Write-Verbose "Driver Package $($PSItem.Name) is not in use" 
        $myTempPackage.ID = $PSItem.PackageID
        $myTempPackage.Name = $PSItem.Name
        $unusedDriverPackages += $myTempPackage
    }
}

#evaluate which driver categories are used
$unusedCategories = @();
Get-CMCategory -CategoryType DriverCategories | ForEach-Object {
    $myTempCategory = [myCategory]::new()
    $myTempCategory.Name = $psitem.LocalizedCategoryInstanceName
    $myTempCategory.ID = $psitem.CategoryInstance_UniqueID
    $tmpCat = $myTempCategory.ID.substring(17)
    If($tmpCat -in $Categories)
    {
        Write-Verbose "Category $CategoryName is in use"
    }
    Else
    {
        Write-Verbose "Category $CategoryName is not in use"
        $unusedCategories += $myTempCategory
    }
}

#delete the drivers
$UnusedDriverObjects.ID| ForEach-Object {
    If ($pscmdlet.ShouldProcess($PSItem, 'Delete driver')) { #whatIf?
        Remove-CMDriver -Id $PSItem -Force 
    }
}
Write-Verbose "Total unused drivers found $($UnusedDriverObjects.count)"

Set-Location $StartingDriveLocation`:

If($HTMLReport)
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
    <tr><th>Name</th><th>ID</th><th>InfFile</th><th>Version</th><th>Categories</th><th>Packages</th><th>Source Path</th></tr>
"@
    $UnusedDriverObjects = $UnusedDriverObjects | Sort-Object -Property Name
    $UnusedDriverObjects | ForEach-Object {
        $tempPackages = $null
        $tempCategories = $null
        $PSItem.Packages | ForEach-Object {
            $tempPackages = "$tempPackages, $PSItem"           
            $tempPackages = $tempPackages.trim(", ")
        }
        $PSItem.Categories | ForEach-Object {
            $tempCategories = "$tempCategories, $PSItem"
        }
        $tempCategories = $tempCategories.Trim(", ")
        $HTML = "$HTML<tr><td>$($PSItem.Name)</td><td>$($PSItem.ID)</td><td>$($PSItem.InfFile)</td><td>$($PSItem.Version)</td><td>$tempCategories</td><td>$tempPackages</td><td>$($PSItem.SourcePath)</td></tr>"
    }
    $html = "$HTML </table>"
    
    $UnusedPackageHTML = 
@"
<H2>Unused Driver Package Information</H2>
    <table>
    <colgroup><col/><col/></colgroup>
    <tr><th>Name</th><th>ID</th></tr>
"@
    $html = "$html $UnusedPackageHTML"
    $unusedDriverPackages | ForEach-Object {
        $HTML = "$HTML<tr><td>$($PSItem.Name)</td><td>$($PSItem.ID)</td></tr>"       
    }
    $html = "$HTML </table>"
    $UnusedCategoryHTML = 
@"
<H2>Unused Category Information</H2>
    <table>
    <colgroup><col/><col/></colgroup>
    <tr><th>Name</th><th>ID</th></tr>
"@
    $html = "$html $UnusedCategoryHTML"
    $unusedCategories | ForEach-Object {
        $HTML = "$HTML<tr><td>$($PSItem.Name)</td><td>$($PSItem.ID)</td></tr>"       
    }
    $html = "$HTML </table>"

    $html = "$HTML </body></html>"
    
}

$HTML | Out-File $HTMLReport -WhatIf:$false
#$UnusedDriverObjects | ConvertTo-Html -Head $a -body "<H2>Unused Driver Information</H2>"| out-file $HTMLReport -WhatIf:$false
#Unused Packages
    
Stop-Transcript