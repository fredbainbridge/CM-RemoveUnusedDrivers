﻿#Find all drivers packages that are not used in a task sequence.
#this will not work if you are relying on an auto apply drivers step that considers all available drivers. (I think)


[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$SiteCode = "LAB",
    [bool]$ignoreWarnings = $true
)
Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"

Start-Transcript -Path "Get-FBInacticeDrivers.log" -Append -Force -WhatIf:$false

set-location $SiteCode`:

function EvaluateTS {
    [CmdletBinding()]
    param(
        $TaskSequenceXML
    )
    $ids = @();  #category or package ID
    $TaskSequenceXML | ForEach-Object {
        if($psitem.name -ne "sequence"){write-verbose "Group:  $($PSItem.name)"}
        if($psitem.step){
            $psitem.step | ForEach-Object {
                if($psitem.type -eq 'SMS_TaskSequence_ApplyDriverPackageAction') 
                { 
                    #write-verbose 'RunCommandLine'
                    Write-Verbose $psitem.name
                    $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('/install:')
                    $PackageID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + '/install:'.Length,8)
                    #if([string]$PackageID -ne ' powersh')
                    #{
                        if(Get-CMDriverPackage -Id $PackageID) 
                        {
                            write-verbose $PackageID
                            $ids += $PackageID
                        }
                    #}
                }
                if($psitem.type -eq 'SMS_TaskSequence_AutoApplyAction') 
                {
                    
                    write-verbose "Step - $($psitem.name)"
                    if((([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('disable="true"') -eq "-1") #not disabled
                    {
                        $index = (([xml]$PSItem.OuterXml).step.OuterXml).IndexOf('DriverCategories:')
                        if($index -ne "-1") 
                        {
                            $CategoryID = (([xml]$PSItem.OuterXml).step.OuterXml).Substring($index + 'DriverCategories:'.Length,36)
                            write-verbose $CategoryID
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
                        }
                    }
                    else
                    {
                        write-verbose "Step is disabled, skipping"
                    }
                    #write-host $CategoryIDs
                }
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
    Write-Verbose "Task Sequence - $($PSItem.Name)"
    $sequence = [xml]$psitem.sequence
    $IDs += EvaluateTS -TaskSequenceXML $sequence.sequence -verbose 
}
$IDs = $IDs | select -Unique
$Categories = $IDs -match ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")
$Packages = $IDs -notmatch ("(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}")
if($Categories -eq $true) {$Categories = $ID} #only one category found
Write-Verbose "All Possible Categories: $Categories"
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

    write-verbose "---------$($myTempDriver.Name)---------"
    
    #is this in a used category?
    if($PSItem.CategoryInstance_UniqueIDs -ne $null)
    {
        $tmpCategories = @();
        $tmpIds = $PSItem.CategoryInstance_UniqueIDs
        $tmpIds | %{($_.ToString()).substring(17)} | ForEach-Object { 
            if($PSItem -in $Categories)
            {
                $InActiveCategory = $true 
                write-verbose "$($myTempDriver.Name) is in active category $PSItem"
            }
            $tmpCategories += $_
        }       
        $myTempDriver.Categories = $tmpCategories
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
    Get-WmiObject -Query "select PackageID from sms_drivercontainer where ci_id = '$($myTempDriver.ID)'" -Namespace "root\sms\site_$SiteCode" | foreach-Object {
            if($PSItem.PackageID -in $Packages) 
            {
                write-verbose "$($myTempDriver.Name) is in active package $($PSitem.PackageID)" 
                $InActivePackage = $true
            }
            $tmpPackages += $PSItem.PackageID
    }
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
    if($PSItem.PackageID -in $packages ) {
        
        Write-verbose "Driver Package $($PSItem.Name) is in use"
    }
    else
    {
        Write-verbose "Driver Package $($PSItem.Name) is not in use" 
        $unusedDriverPackages += $PSItem.PackageID
    }
}

#evaluate which driver categories are used
$unusedCategories = @();
Get-CMCategory -CategoryType DriverCategories | ForEach-Object {
    
    $tmpCat = $psitem.CategoryInstance_UniqueID
    $tmpCat = $tmpCat.substring(17)
    if($tmpCat -in $Categories)
    {
        Write-Verbose "Category $tmpcat is in use"
    }
    else
    {
        write-verbose "Category $tmpCat is not in use"
        $unusedCategories += $tmpCat
    }
}

#delete the drivers
$UnusedDriverObjects.ID| ForEach-Object {
    if ($pscmdlet.ShouldProcess($PSItem, 'Delete driver')) { #whatif?
        Remove-CMDriver -Id $PSItem -force -Verbose
    }
}
write-verbose "Total unused drivers found $($UnusedDriverObjects.count)"

set-location $env:SystemDrive

$UnusedDriverObjects | ConvertTo-Html | out-file UnusedDrivers.html -WhatIf:$false

Stop-Transcript