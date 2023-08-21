<#
.SYNOPSIS
Rename Azure OS Disk.

.DESCRIPTION
Rename Azure VM OS Disk for Linux and Windows.

.NOTES
File Name : Rename-AzOSDisk.ps1
Author   : Microsoft MVP/MCT - Charbel Nemnom
Version  : 1.0
Date     : 13-September-2019
Update   : 17-August-2022
Requires : PowerShell 5.1 or PowerShell 7.2.x (Core)
Module   : Az Module
OS       : Windows or Linux VMs

.LINK
To provide feedback or for further assistance please visit: https://charbelnemnom.com 

.EXAMPLE
.\Rename-AzOSDisk.ps1 -resourceGroup [ResourceGroupName] -VMName [VMName] -osdiskName [OSDiskName] -Verbose
This example will rename the OS Disk for the specified VM, you need to specify the Resource Group name, VM name and the new OS disk name.
Then the script will use the Swap OS disk feature in Azure and change the OS disk on the fly.
#>

[CmdletBinding()]
Param (
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = 'Enter the Resource Group of the VM')]
    [Alias('rg')]
    [String]$resourceGroup,

    [Parameter(Position = 1, Mandatory = $True, HelpMessage = 'Enter Azure VM name')]
    [Alias('VM')]
    [String]$VMName,

    [Parameter(Position = 2, Mandatory = $true, HelpMessage = 'Enter the desired OS Disk name')]
    [Alias('DiskName')]
    [String]$osdiskName

)

#! Install Az Module If Needed
function Install-Module-If-Needed {
    param([string]$ModuleName)
 
    if (Get-Module -ListAvailable -Name $ModuleName) {
        Write-Host "Module '$($ModuleName)' already exists." -ForegroundColor Green
    } 
    else {
        Write-Host "Module '$($ModuleName)' does not exist, installing..." -ForegroundColor Yellow
        Install-Module $ModuleName -Force  -AllowClobber -ErrorAction Stop
        Write-Host "Module '$($ModuleName)' installed." -ForegroundColor Green
    }
}

Install-Module-If-Needed Az.Accounts

#! Check Azure Connection
Try {
    Write-Verbose "Connecting to Azure Cloud..."
    Connect-AzAccount -ErrorAction Stop | Out-Null
}
Catch {
    Write-Warning "Cannot connect to Azure Cloud. Please check your credentials. Exiting!"
    Break
}

#! Install Az Compute Module If Needed
Install-Module-If-Needed Az.Compute

#! Get the details of the VM
Write-Verbose "Get the VM information details: $VMName"
$VM = Get-AzVM -Name $VMName -ResourceGroupName $resourceGroup

#! Get source OS Disk information
Write-Verbose "Get the source OS Disk information: $($VM.StorageProfile.OsDisk.Name)"
$sourceOSDisk = Get-AzDisk -ResourceGroupName $resourceGroup -DiskName $VM.StorageProfile.OsDisk.Name

#! Create the managed disk configuration
Write-Verbose "Create the managed disk configuration..."
$diskConfig = New-AzDiskConfig -SkuName $sourceOSDisk.Sku.Name -Location $VM.Location `
    -DiskSizeGB $sourceOSDisk.DiskSizeGB -SourceResourceId $sourceOSDisk.Id -CreateOption Copy

#! Create the new disk
Write-Verbose "Create the new OS disk..."
$newOSDisk = New-AzDisk -Disk $diskConfig -DiskName $osdiskName -ResourceGroupName $resourceGroup

#! Swap the OS Disk
Write-Verbose "Swap the OS disk to: $osdiskName"
Set-AzVMOSDisk -VM $VM -ManagedDiskId $newOSDisk.Id -Name $osdiskName | Out-Null
Write-Verbose "The VM is rebooting..."
Update-AzVM -ResourceGroupName $resourceGroup -VM $VM

#! Delete the old OS Disk
$delete = Read-Host "Do you want to delete the original OS Disk [y/n]"
If ($delete -eq "y" -or $delete -eq "Y") {
    Write-Warning "Deleting the old OS Disk: $($sourceOSDisk.Name)"
    Remove-AzDisk -ResourceGroupName $resourceGroup -DiskName $sourceOSDisk.Name -Force -Confirm:$false
}
