# Variables
param
(
    [Parameter(Mandatory = $true)]
    [string]$subscription,
    [Parameter(Mandatory = $true)]
    [string]$resourceGroup,
    [Parameter(Mandatory = $true)]
    [string]$ogvmName,
    [Parameter(Mandatory = $true)]
    [string]$location,
    [Parameter(Mandatory = $true)]
    [string]$zone,
)



function mainExecution{
    $UniqueRandomString = "az"
    $newvmName = $ogvmName
		try{
			# Set the subscription
			Set-AzContext -Subscription $subscription
			# Check if there is a 'no_delete' lock on the resource group
			$lock = Get-AzResourceLock -ResourceGroupName $resourceGroup -LockName <Specify your Lock name here> -ErrorAction SilentlyContinue
			if ($lock) {
				Write-Verbose "Removing lock on the resource group..."
				Remove-AzResourceLock -ResourceGroupName $resourceGroup -LockName <Specify your Lock name here> -Force
			}else {
				Write-Verbose "No Lock is there"}
			# Get the details of the VM to be moved to the Availability Set
			Write-Verbose "Getting details of the original VM $ogvmName"
			$originalVM = Get-AzVM -ResourceGroupName $resourceGroup -Name $ogvmName
			#Storing Tags which is on the VM
			$tagging=$originalVM.Tags
			# Stop the VM to take a snapshot
			Write-Verbose "Stopping the VM..."
			Stop-AzVM -ResourceGroupName $resourceGroup -Name $ogvmName -Force 
		}
		catch {
			Write-Error "An error occurred while getting details, removing 'no_delete' lock, or stopping the original VM: $_"
			break
		}
	 
		try {
			# Create a Snapshot of the OS disk and then, create an Azure Disk with Zone information
			Write-Verbose "Creating a snapshot of the OS disk..."
			$snapshotOSConfig = New-AzSnapshotConfig -SourceUri $originalVM.StorageProfile.OsDisk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_LRS -Tag $tagging
			$OSSnapshot = New-AzSnapshot -Snapshot $snapshotOSConfig -SnapshotName ($originalVM.StorageProfile.OsDisk.Name + "-snapshot") -ResourceGroupName $resourceGroup 
			$diskSkuOS = (Get-AzDisk -DiskName $originalVM.StorageProfile.OsDisk.Name -ResourceGroupName $originalVM.ResourceGroupName).Sku.Name
			Write-Verbose "Creating a disk from the OS snapshot..."
			$diskConfig = New-AzDiskConfig -Location $OSSnapshot.Location -SourceResourceId $OSSnapshot.Id -CreateOption Copy -SkuName  $diskSkuOS -Zone $zone -Tag $tagging 
			$OSdisk = New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroup -DiskName ($newvmname + "-osdisk" + $UniqueRandomString + $zone)
			#Get-AzureRmResource -name testvm| foreach { Set-AzureRmResource -ResourceId $_.resourceid -Tag $tag -Force}
		}
		catch {
			Write-Error "An error occurred while creating a snapshot or disk from the OS disk: $_"
			return
		}
		try {
			# Create the basic configuration for the replacement VM
			$newVM = New-AzVMConfig -VMName $newvmname -VMSize $originalVM.HardwareProfile.VmSize  -Zone $zone -Tag $tagging
		}
		catch {
			Write-Error "An error occurred while creating the basic configuration for the replacement VM: $_"
			return
		}
		try {
			# Create a Snapshot from the Data Disks and the Azure Disks with Zone information
			$i=0
			foreach ($disk in $originalVM.StorageProfile.DataDisks) { 
				Write-Verbose "Creating a snapshot of data disk $($disk.Name)..."
				$snapshotDataConfig = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id -Location $location -CreateOption copy -SkuName Standard_LRS -Tag $tagging
				$DataSnapshot = New-AzSnapshot -Snapshot $snapshotDataConfig -SnapshotName ($disk.Name + '-snapshot') -ResourceGroupName $resourceGroup
				$diskSkuData = (Get-AzDisk -DiskName $disk.Name -ResourceGroupName $originalVM.ResourceGroupName).Sku.Name
				Write-Verbose "Creating a disk from the data snapshot..."
				$datadiskConfig = New-AzDiskConfig -Location $DataSnapshot.Location -SourceResourceId $DataSnapshot.Id -CreateOption Copy -SkuName $diskSkuData -Zone $zone -Tag $tagging
				$datadisk = New-AzDisk -Disk $datadiskConfig -ResourceGroupName $resourceGroup -DiskName ($newvmname + "-datadisk" + $i + $UniqueRandomString + $zone)
				$i++
				Add-AzVMDataDisk -VM $newVM -Name $datadisk.Name -ManagedDiskId $datadisk.Id -Caching $disk.Caching -Lun $disk.Lun -DiskSizeInGB $disk.DiskSizeGB -CreateOption Attach 
			}
		}
		catch {
			Write-Error "An error occurred while creating a snapshot or disk from the data disk: $_"
			return
		}
	 
		try {
			# Detach OS disk
			Write-Verbose "Setting delete option as Detach"
			#Remove-AzVMDataDisk -ResourceGroupName $resourceGroup -VM $ogvmName -DiskName $originalVM.StorageProfile.OsDisk.Name
			$originalVM.StorageProfile.OsDisk.DeleteOption = 'Detach'
		}
		catch {
			Write-Error "An error occurred while detaching OS disk: $_"
			return
		}
  
# NOTE - No need to Detach Data Disks, as by default DeleteOption for Data Disks is set as Detach

		try {
			# Remove the original VM
			Write-Verbose "Removing the original VM..."
			Remove-AzVM -ResourceGroupName $resourceGroup -Name $ogvmName -Force
		}
		catch {
			Write-Error "An error occurred while removing the original VM: $_"
			return
		}
		try {
			# Add the pre-existing OS disk 
			Write-Verbose "Attaching the pre-existing OS disk to the new VM..."
			Set-AzVMOSDisk -VM $newVM -CreateOption Attach -ManagedDiskId $OSdisk.Id -Name $OSdisk.Name -Linux   # Note - Fow Windows VM, change -Linux to -Windows
		}
		catch {
			Write-Error "An error occurred while attaching the pre-existing OS disk: $_"
			return
		}
		try {
			# Add NIC(s) and keep the same NIC as primary
			# If there is a Public IP from the Basic SKU remove it because it doesn't support zones
			foreach ($nic in $originalVM.NetworkProfile.NetworkInterfaces) {
				if ($nic.Primary -eq "True") {
					Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id -Primary
				}
				else {
					Add-AzVMNetworkInterface -VM $newVM -Id $nic.Id 
				}
			}
		}
		catch {
			Write-Error "An error occurred while adding NIC(s) to the new VM: $_"
			return
		}
		try {
			# Recreate the VM
			Write-Verbose "Recreating the new VM..."
			#New-AzVM -ResourceGroupName $resourceGroup -Location $originalVM.Location -VM $newVM -DisableBginfoExtension
			New-AzVM -ResourceGroupName $resourceGroup -Location $originalVM.Location -VM $newVM -DisableBginfoExtension
		}
		catch {
			Write-Error "An error occurred while recreating the new VM: $_"
			return
		}
	 
		# Validate the number of data disks on the original VM and the new VM
			$originalDataDiskCount = $originalVM.StorageProfile.DataDisks.Count
			$newDataDiskCount = $newVM.StorageProfile.DataDisks.Count
			if ($originalDataDiskCount -ne $newDataDiskCount) {
				Write-Error "Validation failed: The number of data disks on the original VM ($originalDataDiskCount) does not match the number on the new VM ($newDataDiskCount)."
				return
			}else{
				Write-host "Validation Passed: The number of data disks on the original VM ($originalDataDiskCount) matches the number on the new VM ($newDataDiskCount)."
				}
}
