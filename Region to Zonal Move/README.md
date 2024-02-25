# Move Azure Virtual Machine from Region to Any Zone or Zone to Zone through PowerShell script

### In Azure, we can't move a VM to Zone if it is not already in Zone. We are developing a custom script which can solve this problem.
### Our aim is to seamlessly move VM into Zone also with minimal Down time, so it'll be easy for any Production Environment as well.

## Steps :
* First we'll be taking all required variables to proceed with our script
* Then in Execution Phase we'll be implementing the actual script
  - a. Remove Lock
  - b. VM Power Status should Stopped (deallocated)
  - c. Take Snapshot (Os Disk and Data Disk)
  - d. Create New Disks from Snapshot (OS and Data Disks) Zone Specific - we'll be moving Disks in Zone too.
  - e. Delete the Existing VM confis
  - f. Create VM with existing configurations into Availability Zone
  - g. Check VM Health Status (Power and Agent status, Ping)
