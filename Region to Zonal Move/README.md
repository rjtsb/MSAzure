# Move Azure Virtual Machine from Region to Any Zone or Zone to Zone through PowerShell script

### In Azure, we can't move a VM to Zone if it is not already in Zone. Also zone to zone movement is time taking process in Azure. We are developing a custom script which can solve this problem.
### Our aim is to seamlessly move VM into Zone also with minimal Down time, so it'll be easy for any Production Environment as well.

## Steps :
* First we'll be taking all required variables to proceed with our script
* Execute dependency validations
  - a. VM Exist or not
  - b. Get VM details
  - c. Health status (Power State, Agent Status), Last Successful Backup should less than 24hrs
  - d. Export VM Configs as xml
  - e. Resource Delete options (OS and Data disks, NIC) set it as Detach instead of Delete
  - f. Subscription and SKUs Quota as per Zone
  - g. Lock
  - h. Diagnostic Storage account
### Note: If all success, good to go otherwise exit.
* Then in Execution Phase we'll be implementing the actual script
  - a. Remove Lock
  - b. VM Power Status should Stopped (deallocated)
  - c. Take Snapshot (Os Disk and Data Disk)
  - d. Create New Disks from Snapshot (OS and Data Disks) Zone Specific - we'll be moving Disks in Zone too.
  - e. Delete the Existing VM confis
  - f. Create VM with existing configurations into Availability Zone
  - g. Check VM Health Status (Power and Agent status, Ping)
