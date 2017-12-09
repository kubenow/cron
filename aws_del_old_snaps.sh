#!/bin/bash
# Script to delete old unpaired snapshots

# Current list of regions we work with
aws_regions=("ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2" "us-east-1" "us-east-2" "us-west-1" "us-west-2")

echo -e "\n----------------------------------\n   $(date)   \n----------------------------------"
echo -e "Amazon Web Services - Looking for old unpaired snaposhots:\n "

# Now we start the process of deregistering the old Kubenow AMI across all the other regions
for reg in ${aws_regions[*]}; do

  # We update the default region so to correctly perform checks in each region via awscli
  AWS_DEFAULT_REGION="$reg"
  echo -e "Current region is: $AWS_DEFAULT_REGION\n"

  # Extracting both KubeNow images that are flagged as "test" or "current"
  aws ec2 describe-snapshots --owner-ids 105135433346 --query 'Snapshots[*].{ID:SnapshotId,Description:Description}' >/tmp/aws_snaps.json
  sed -i '1s/^/{"Snapshots":/' /tmp/aws_snaps.json
  sed -i "$ a }" /tmp/aws_snaps.json
  tot_no_snaps=$(grep -c -i ID </tmp/aws_snaps.json)
  counter_del_snap=0

  if [ "$tot_no_snaps" -gt "0" ]; then
    # Finding if the AMI which the current snapshot has been created for still exist. If not, we can delete snapshot
    echo -e "Total of current snapshot is: $tot_no_snaps\n"

    index=0
    while [ "$index" -lt "$tot_no_snaps" ]; do

      # Extracting AMI's ID from snapshot's description field
      ami_id_to_check=$(jq ".Snapshots[$index] | .Description" /tmp/aws_snaps.json | grep -E -o -m1 "ami-([a-z0-9]*)")
      snap_id=$(jq ".Snapshots[$index] | .ID" /tmp/aws_snaps.json | sed -e 's/^"//' -e 's/"$//')

      # When copying an AMI from one region to another, both the source and the destination AMI ids are listed. We need to keep and check only first id
      no_of_rel_amis=$(echo "$ami_id_to_check" | wc -w)

      if [ "$no_of_rel_amis" == "0" ] && [ -z "$ami_id_to_check" ]; then
        # This should never happen. However if something goes wrong, then we avoid to call APIs which will fail otherwise
        echo -e "Oops. Something went wrong at this point.\nNo of AMI ids to be checked seems zero. This should not be the case\n"
        exit 1
      elif [ "$no_of_rel_amis" -gt "1" ]; then
        ami_id_to_check=$(echo "$ami_id_to_check" | awk NR==1'{print $1}')
      fi

      echo -e "Snapshot id: $snap_id"
      echo -e "Related AMI Id to be checked: $ami_id_to_check"

      # Checking whether or not AMI still exists
      aws ec2 describe-images --image-ids "$ami_id_to_check" >/tmp/output_AMI_check 2>/tmp/out_err_AMI_check
      aws_exit_code=$?
      aws_string_err=$(grep -o "does not exist" </tmp/out_err_AMI_check)

      if [ "$aws_exit_code" == "0" ]; then
        echo -e "AMI id: $ami_id_to_check still exists. Snapshot id: $snap_id will not be deleted.\n"
      elif [ "$aws_exit_code" == "255" ] && [ -n "$aws_string_err" ]; then
        echo -e "AMI id: $ami_id_to_check does not exist anymore. Snapshot id: $snap_id will be deleted.\n"
        echo -e "Deleting the snapshots id: $snap_id \n"
        aws ec2 delete-snapshot --snapshot-id "$snap_id"
        counter_del_snap=$((counter_del_snap + 1))
      fi

      index=$((index + 1))
    done

    if [ "$counter_del_snap" == "0" ]; then
      echo -e "No old unpaired snapshots were found \n"
    fi
  else
    echo -e "There are no available snapshots in the current region: $AWS_DEFAULT_REGION"
  fi

  echo -e "\nNo of deleted of snapshots: $counter_del_snap\nDone.\n"
done
