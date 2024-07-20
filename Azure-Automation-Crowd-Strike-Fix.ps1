az extension add -n vm-repair

$subscription = "<subpcription ID here>"
$resourcegroupName = "<Resource Grop Name here>"
$VMNAME = "<VMName here>"

az login
az account set -s $subscription

az vm repair create -g $resourcegroupName -n $VMNAME --unlock-encrypted-vm  --repair-username  cloudstroke
az vm repair run -g $resourcegroupName -n $VMNAME --run-on-repair --run-id win-crowdstrike-fix-bootloop
az vm repair restore -g $resourcegroupName -n $VMNAME --yes
