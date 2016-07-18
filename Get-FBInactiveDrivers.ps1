#Find all drivers packages that are not used in a task sequence.
#
#If a driver is not referenced in an apply driver step (category or driver package) and 
#is not part of a boot image, it is considered not in use.
#
#"Warnings" are generated if there are apply driver steps that use all drivers. 
#In order for this to be most accurate you should first cleanup or delete and legacy task sequences.
#This will find any driver referenced in all task sequences.
#Using -WhatIf the first time you run this script is highly recommended
#

##
#To do 
#Get category name instead of GUID in output. (done)
#Add unused packages and categories to the HTML output
##

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SiteCode = "LAB",
    [string]$SiteServer = "CM01",
    [string]$HTMLReport = "UnusedDrivers.html",
    [switch]$IgnoreWarnings = $true
)

import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -Verbose:$false

Start-Transcript -Path "Get-FBInactiveDrivers.log" -Append -Force -WhatIf:$false
$StartingDriveLocation = $pwd.Drive.Name
set-location $SiteCode`:

function EvaluateTS {
    [CmdletBinding()]
    param(
        $TaskSequenceXML
    )
    $ids = @();  #category or package ID
    $TaskSequenceXML | ForEach-Object {
        #if($psitem.name -ne "sequence"){write-verbose "Group:  $($PSItem.name)"}
        if($psitem.step){
            $psitem.step | ForEach-Object {
                if ((([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('disable="true"') -eq "-1") #ensure the step isn't disabled.
                {
                    if($psitem.type -eq 'SMS_TaskSequence_ApplyDriverPackageAction') 
                    { 
                        #write-verbose 'SMS_TaskSequence_ApplyDriverPackageAction'
                        $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('/install:')
                        $PackageID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + '/install:'.Length,8)
                        Write-Verbose "Driver Package: $PackageID found in step `"$($psitem.name)`" "
                        $ids += $PackageID
                    }
                    if($psitem.type -eq 'SMS_TaskSequence_AutoApplyAction') 
                    {
                        $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('DriverCategories:')
                        if($index -ne "-1") 
                        {
                            $CategoryID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + 'DriverCategories:'.Length,36)
                            write-verbose "Driver Category $CategoryID found in Step - $($psitem.name)"
                            $ids += $CategoryID
                        }
                        else
                        {
                            Write-Verbose "This task sequence step applies drivers from all categories and is not disabled.  This makes it impossible to determine what drivers are not being used.  This should be a build and capture task sequence or something else expected."
                            if( -not $ignoreWarnings)
                            {
                                $response = Read-Host -Prompt "Warning! Continue? Y/N"
                                if( $response.ToUpper() -ne "Y" ) { exit }
                            }
                            else
                            {
                                Write-Verbose "Ignoring Warning"
                            }
                        }
                    }
                } 
                else
                {
                    write-verbose "Driver step $($psitem.name) is disabled, skipping"
                } #end of disabled step check
            } #end of steps
        }
        if($psitem.group)
        {
            $ids += EvaluateTS -TaskSequenceXML $psitem.group -verbose  
        }

    }
    #write-output $CategoryIDs -verbose
    #Write-Output $packageIDs -verbose
    write-output $ids
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
if($Categories -eq $true) {$Categories = $ID} #only one category found
Write-Verbose "All Categories in use : "
$Categories | ForEach-Object { write-verbose $PSItem}
Write-Verbose "All Packages in use : "
$Packages | ForEach-Object { write-verbose $PSItem}
#get drivers IDs used in boot images
$driversInBootMedia = @();
Write-Verbose "Looking for drivers referenced by boot images"
Get-CMBootImage | ForEach-Object {
    $bootImageName = $psitem.name
    $PSItem.ReferencedDrivers | ForEach-Object {
        $driversInBootMedia += $PSItem.id
        write-verbose "Found driver $($psitem.id) in boot image $bootImageName"
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
    

    write-verbose "---------$($myTempDriver.Name)---------"
    
    #is this in a used category?
    if($PSItem.CategoryInstance_UniqueIDs -ne $null)
    {
        $tmpCategories = @();
        $tmpCategoriesNames = @();
        $tmpIds = $PSItem.CategoryInstance_UniqueIDs
        $tmpIds | %{($_.ToString()).substring(17)} | ForEach-Object { 
            if($PSItem -in $Categories)
            {
                $InActiveCategory = $true 
                write-verbose "$($myTempDriver.Name) is in active category $PSItem"
            }
            $tmpCategories += $PSItem
            $tmpCategoriesNames += (Get-CMCategory -Id "DriverCategories:$PSItem").LocalizedCategoryInstanceName
        }       
        $myTempDriver.Categories = $tmpCategoriesNames
    }
    if(-not $InActiveCategory) {
        Write-verbose "$($myTempDriver.Name) is not in an active category"
    }
    
    #is this in a used driver package?
    <#$packages | ForEach-Object {
        Get-WmiObject -Query "select * from sms_drivercontainer where packageID = '$PSitem' and ci_id = '$DriverID'" -Namespace "root\sms\site_$SiteCode" | foreach-Object {
            write-verbose "$DriverName is in active package $($PSitem.PackageID)" 
            $InActivePackage = $true
        }
    }
    #>
    $tmpPackages = @();
    Get-WmiObject -Query "select PackageID from sms_drivercontainer where ci_id = '$($myTempDriver.ID)'" -Namespace "root\sms\site_$SiteCode" -ComputerName $SiteServer| foreach-Object {
            if($PSItem.PackageID -in $Packages) 
            {
                write-verbose "$($myTempDriver.Name) is in active package $($PSitem.PackageID)" 
                $InActivePackage = $true
            }
            $tmpPackages += $PSItem.PackageID
    }
    $myTempDriver.Packages = $tmpPackages

    if( -not $InActivePackage)
    {
        write-verbose "$($myTempDriver.Name) is not in an active package " 
    }
    
    #is it boot media?
    if($myTempDriver.ID -in $driversInBootMedia)
    {
        write-verbose "$($myTempDriver.Name), drive Id: $($MyTempDriver.ID) is used for boot media"
        $InBootMedia = $true
    }
    else
    {
        write-verbose "$($myTempDriver.Name) is not in a boot media"
    }
    if(-not $InActiveCategory -and (-not $InActivePackage) -and (-not $InBootMedia))  #this is an unused driver.
    {
        $UnusedDriverObjects += $myTempDriver
        write-verbose "$($myTempDriver.Name), ID: $($MyTempDriver.ID) is unused and can be deleted."
    }
}

#$UnusedDriverObjects | select LocalizedDisplayName, DriverInfFile, DriverVersion

#evaluate if driver packages are used
#Unused Driver Packages.  This is unlikely to be super helpful.  Drivers in packages will also have categories.  
write-verbose "Looking for unused driver packages.  This is not super helpful"
$unusedDriverPackages = @();
Get-CMDriverPackage | ForEach-Object {
    $myTempPackage = [myPackage]::new()
    if($PSItem.PackageID -in $packages ) {
        
        Write-verbose "Driver Package $($PSItem.Name) is in use"
    }
    else
    {
        Write-verbose "Driver Package $($PSItem.Name) is not in use" 
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
    if($tmpCat -in $Categories)
    {
        Write-Verbose "Category $CategoryName is in use"
    }
    else
    {
        write-verbose "Category $CategoryName is not in use"
        $unusedCategories += $myTempCategory
    }
}

#delete the drivers
$UnusedDriverObjects.ID| ForEach-Object {
    if ($pscmdlet.ShouldProcess($PSItem, 'Delete driver')) { #whatif?
        Remove-CMDriver -Id $PSItem -force -Verbose
    }
}
write-verbose "Total unused drivers found $($UnusedDriverObjects.count)"

set-location $StartingDriveLocation`:

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