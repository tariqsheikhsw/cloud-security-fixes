
!/bin/bash
Read instance IDs from the file

input="instance_ids.txt"

while IFS= read -r INSTANCE_ID

do

echo "Processing instance ID: $INSTANCE_ID"
Step 1: Create a snapshot of the EBS root volume of the affected instance

ROOT_VOLUME_ID=$(aws ec2 describe-instances --instance-id $INSTANCE_ID --query "Reservations[].Instances[].BlockDeviceMappings[?DeviceName==`/dev/sda1`].Ebs.VolumeId" --output text)

SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id $ROOT_VOLUME_ID --description "Snapshot of root volume of instance $INSTANCE_ID" --query "SnapshotId" --output text)
Step 2: Create a new EBS Volume from the snapshot in the same availability zone

AVAILABILITY_ZONE=$(aws ec2 describe-instances --instance-id $INSTANCE_ID --query "Reservations[].Instances[].Placement.AvailabilityZone" --output text)

NEW_VOLUME_ID=$(aws ec2 create-volume --snapshot-id $SNAPSHOT_ID --availability-zone $AVAILABILITY_ZONE --query "VolumeId" --output text)

### Step 3: Launch a new Windows instance in that availability zone using a different version of Windows

NEW_INSTANCE_ID=$(aws ec2 run-instances --image-id <new-windows-ami-id> --instance-type <instance-type> --key-name <key-pair> --subnet-id <subnet-id> --security-group-ids <security-group-id> --placement "AvailabilityZone=$AVAILABILITY_ZONE" --query "Instances[0].InstanceId" --output text)
Step 4: Attach the EBS volume from step (2) to the new Windows instance as a data volume

aws ec2 attach-volume --volume-id $NEW_VOLUME_ID --instance-id $NEW_INSTANCE_ID --device /dev/sdf
Wait for the volume to be attached

aws ec2 wait volume-in-use --volume-ids $NEW_VOLUME_ID
Step 5: Use Systems Manager to delete the file
Ensure the instance is registered with SSM

aws ssm wait instance-exists --instance-ids $NEW_INSTANCE_ID
Create the SSM document for the PowerShell script

SSM_DOCUMENT_NAME="DeleteCrowdStrikeFile_$INSTANCE_ID"

aws ssm create-document --name $SSM_DOCUMENT_NAME --document-type "Command" --content '{

"schemaVersion": "2.2",

"description": "Delete CrowdStrike file",

"mainSteps": [

{

"action": "aws:runPowerShellScript",

"name": "deleteCrowdStrikeFile",

"inputs": {

"runCommand": [

"Remove-Item -Path D:\\Windows\\System32\\drivers\\CrowdStrike\\C00000291*.sys -Force"

]

}

}

]

}'
Execute the SSM document

COMMAND_ID=$(aws ssm send-command --instance-ids $NEW_INSTANCE_ID --document-name $SSM_DOCUMENT_NAME --query "Command.CommandId" --output text)
Wait for the command to complete

aws ssm wait command-executed --instance-id $NEW_INSTANCE_ID --command-id $COMMAND_ID
Step 6: Detach the EBS volume from the new Windows instance

aws ec2 detach-volume --volume-id $NEW_VOLUME_ID
Wait for the volume to be detached

aws ec2 wait volume-available --volume-ids $NEW_VOLUME_ID
Step 7: Create a snapshot of the detached EBS volume

NEW_SNAPSHOT_ID=$(aws ec2 create-snapshot --volume-id $NEW_VOLUME_ID --description "Snapshot after deleting C00000291*.sys" --query "SnapshotId" --output text)
Step 8: Replace the root volume of the original instance with the new snapshot

NEW_ROOT_VOLUME_ID=$(aws ec2 create-volume --snapshot-id $NEW_SNAPSHOT_ID --availability-zone $AVAILABILITY_ZONE --query "VolumeId" --output text)
Stop the original instance

aws ec2 stop-instances --instance-ids $INSTANCE_ID
Wait for the instance to stop

aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
Detach the original root volume

aws ec2 detach-volume --volume-id $ROOT_VOLUME_ID
Wait for the volume to be detached

aws ec2 wait volume-available --volume-ids $ROOT_VOLUME_ID
Attach the new root volume

aws ec2 attach-volume --volume-id $NEW_ROOT_VOLUME_ID --instance-id $INSTANCE_ID --device /dev/sda1
Step 9: Start the original instance

aws ec2 start-instances --instance-ids $INSTANCE_ID
Cleanup: Terminate the new instance

aws ec2 terminate-instances --instance-ids $NEW_INSTANCE_ID
Wait for the instance to terminate

aws ec2 wait instance-terminated --instance-ids $NEW_INSTANCE_ID
Delete the SSM document

aws ssm delete-document --name $SSM_DOCUMENT_NAME

echo "Completed processing for instance ID: $INSTANCE_ID"

done < "$input"

echo "All instances processed."
