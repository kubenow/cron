#!/bin/bash
# Script to delete AMI older than n no of days

# Exit immediately if a command exits with a non-zero status
set -e

# Installing necessary tool for the script: awscli and jq
sudo apt-get update && sudo apt-get upgrade
sudo apt-get install awscli jq -y

# Current list of regions we work with
aws_regions=("ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2" "us-east-1" "us-east-2" "us-west-1" "us-west-2")

echo -e "----------------------------------\n   $(date)   \n----------------------------------"
del_date=$(date +"%Y-%m-%d" --date="1 days ago")
echo -e "Amazon Web Services - Looking for old KubeNow's AMIs:\n "

# Now we start the process of deregistering the old Kubenow AMI across all the other regions
for reg in ${aws_regions[*]}; do
        
        # We update the default region so to correctly perform checks in each region via awscli
        AWS_DEFAULT_REGION="$reg"
        printf "Current region is: %s\n" "$AWS_DEFAULT_REGION"
        
        # Extracting both KubeNow images that are flagged as "test" or "current"
        aws ec2 describe-images --filters "Name=name,Values=kubenow-*-*" > /tmp/aws_out_images.json
        tot_no_amis=$(grep -c -i imageid < /tmp/aws_out_images.json)

        if [ "$tot_no_amis" -gt "0" ]; then
            # Finding Image IDs of AMIs older than 3 days which needed to be deregistered
            counter_del_img=0
            counter_del_snap=0
            index=0
            while [ "$index" -lt "$tot_no_amis" ]; do

                img_date=$(jq ".Images[$index] | .CreationDate" /tmp/aws_out_images.json | sed -e 's/^"//' -e 's/"$//' -e 's/T.*//')

                if [ "$img_date" == "$del_date" ]; then
                    # Extracting AMI's "Name" and "ImageId"
                    name=$(jq ".Images[$index] | .Name" /tmp/aws_out_images.json | sed -e 's/^"//' -e 's/"$//')
                    ami_id_to_deregister=$(jq ".Images[$index] | .ImageId" /tmp/aws_out_images.json | sed -e 's/^"//' -e 's/"$//')
                    echo -e "Following old AMI dated $img_date is found \nName: $name \nAMI ID:$ami_id_to_deregister\n"

                    # Find if there are any snapshots attached to the Image need to be deregister
                    aws ec2 describe-images --image-ids "$ami_id_to_deregister" | grep snap | awk ' { print $2 }' | sed -e 's/^"//' -e 's/,$//' -e 's/"$//' > /tmp/old_snaps.txt                  
                    
                    # Deregistering the AMI
                    echo -e "Starting the deregister of KubewNow AMI: $ami_id_to_deregister...\n"
                    aws ec2 deregister-image --image-id "$ami_id_to_deregister"
                    counter_del_img=$((counter_del_img+1))
                    
                    # Deleting snapshots attached to AMI
                    while read -r line; do 
                        echo -e "Deleting the associated snapshots: $line \n"
                        aws ec2 delete-snapshot --snapshot-id "$line"
                        counter_del_snap=$((counter_del_snap+1))
                    done < /tmp/old_snaps.txt
                fi

                index=$((index+1))
            done
            
            if [ "$counter_del_img" == "0" ]; then
                echo -e "No old images dated $del_date were found \n"
            fi
            
        else
            echo -e "No KubeNow AMIs flagged as test or current found"
        fi
done

# Now taking care of the S3 bucket for KubeNow images. Extracting List of objects
echo -e "AWS S3 - Looking for old KubeNow bucket objects:\n"
aws s3 ls s3://kubenow-us-east-1 --region us-east-1 --human-readable | grep -E 'kubenow-v([0-9]*)([ab0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*).qcow2' > /tmp/aws_s3_objs.txt

no_obj_to_check=$(wc -l < /tmp/aws_s3_objs.txt)
echo -e "No of bucket object to be checked: $no_obj_to_check\n"

counter_del_s3_obj=0

if [ "$no_obj_to_check" -gt "0" ]; then

    while read -r line; do
        obj_date=$(echo $line | awk {'print $1'})
        obj_name=$(echo $line | awk {'print $5'})
    
        if [ "$obj_date" == "$del_date" ]; then
            echo -e "Following old KubeNow bucket object dated: $obj_date is found\nName: $obj_name\n"
            echo -e "Starting the delete bucket object: $obj_name...\n"
            aws s3 rm "s3://kubenow-us-east-1/$obj_name"
            counter_del_s3_obj=$((counter_del_s3_obj+1))
        fi
    done < /tmp/aws_s3_objs.txt
    
    if [ "$counter_del_s3_obj" == "0" ]; then
        echo -e "No old bucket objects dated $del_date were found \n"
    fi
    
else
   echo -e "\nNo KubeNow bucket objects flagged as test or current found"
fi

echo -e "\nNo of deleted of AMI: $counter_del_img\nNo of deleted snapshots: $counter_del_snap\nNo of deleted bucket object: $counter_del_s3_obj\nDone.\n"
