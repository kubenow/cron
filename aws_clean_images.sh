#!/bin/bash
# shellcheck disable=SC2126
# The above is an exception for the grep command around line 43, for variable tot_no_images

# Exit immediately if a command exits with a non-zero status
set -e

# Execute different script only for AWS and before main ones
# Reason is to avoid concurrent APIs call (e.g. deletion of an AMI and checking if that AMI exists)
bash aws_del_old_snaps.sh

# Installing necessary tool for the script: awscli and jq
pip install awscli --upgrade --user

# Current list of regions we work with
aws_regions=("ca-central-1" "eu-central-1" "eu-west-1" "eu-west-2" "us-east-1" "us-east-2" "us-west-1" "us-west-2")

# Debugging: - All of sudden ec2 api is not working with: TO BE REMOVED
# "ca-central-1" "eu-central-1" "eu-west-2" "us-east-2"

echo -e "----------------------------------\n   $(date)   \n----------------------------------"
del_date=$(date +"%Y-%m-%d" --date="1 days ago")
echo -e "Amazon Web Services - Looking for old KubeNow's AMIs:\n "

# Now we start the process of deregistering the old Kubenow AMI across all the other regions
for reg in ${aws_regions[*]}; do
        
        # We update the default region so to correctly perform checks in each region via awscli
        export AWS_DEFAULT_REGION="$reg"
        printf "Current region is: %s\n" "$AWS_DEFAULT_REGION"
        
        # Extracting both KubeNow images that are flagged as "test" or "current"
        aws ec2 describe-images --filters "Name=name,Values=kubenow-*-*" "Name=owner-id,Values=105135433346" > /tmp/aws_out_images.json
        tot_no_amis=$(grep -i "imageid" < /tmp/aws_out_images.json | wc -l)
        counter_del_img=0
        counter_del_snap=0

        if [ "$tot_no_amis" -gt "0" ]; then
            # Finding Image IDs of AMIs older than 1 day which needed to be deregistered
            index=0
            while [ "$index" -lt "$tot_no_amis" ]; do

                img_date=$(jq ".Images[$index] | .CreationDate" /tmp/aws_out_images.json | sed -e 's/^"//' -e 's/"$//' -e 's/T.*//')

                if [[ ! "$img_date" > "$del_date" ]]; then
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
        
        echo -e "\nNo of deleted of AMI: $counter_del_img\nNo of deleted snapshots: $counter_del_snap\n"
done

# Now taking care of the S3 buckets for KubeNow images
s3_buckets=("us-east-1" "eu-central-1")

#  Extracting List of objects from each bucket
for buck in ${s3_buckets[*]}; do

    echo -e "AWS S3 $buck - Looking for old KubeNow bucket objects:\n"
    # Technicality here about the set -e at the beginning at grep's exit code -1. Thus using tee which no matter the outcomes, will return 0
    aws s3 ls s3://kubenow-"$buck" --region "$buck" --human-readable | grep -E 'kubenow-v([0-9]*)([ab0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*).qcow2([.md5]*)' | tee /tmp/aws_s3_objs.txt

    no_obj_to_check=$(wc -l < /tmp/aws_s3_objs.txt)
    echo -e "No of bucket object to be checked: $no_obj_to_check\n"

    counter_del_s3_obj=0

    if [ "$no_obj_to_check" -gt "0" ]; then

        while read -r line; do
            obj_date=$(echo "$line" | awk '{print $1}')
            obj_name=$(echo "$line" | awk '{print $5}')

            if [[ ! "$obj_date" > "$del_date" ]]; then
                echo -e "Following old KubeNow bucket object dated: $obj_date is found\nName: $obj_name\n"
                echo -e "Starting the delete bucket object: $obj_name...\n"
                aws s3 rm "s3://kubenow-$buck/$obj_name" --region "$buck"
                counter_del_s3_obj=$((counter_del_s3_obj+1))
            fi
        done < /tmp/aws_s3_objs.txt

        if [ "$counter_del_s3_obj" == "0" ]; then
            echo -e "No old bucket objects dated $del_date were found \n"
        fi

    else
       echo -e "\nNo KubeNow bucket objects flagged as test or current found"
    fi

    echo -e "\nNo of deleted bucket object: $counter_del_s3_obj\n"
done

echo -e "Done.\n"
