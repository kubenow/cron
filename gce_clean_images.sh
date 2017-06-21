#!/bin/bash
# Script to delete GCE images older than n no of days

# Exit immediately if a command exits with a non-zero status
set -e

# Installing necessary tool for the script: gce sdk kit and jq
# Create an environment variable for the correct distribution
CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
export CLOUD_SDK_REPO

# Add the Cloud SDK distribution URI as a package source
echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

# Import the Google Cloud Platform public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

# Update the package list and install the Cloud SDK
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install google-cloud-sdk jq -y

# Performing authentication in GCE
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/gce-key.json"
gcloud auth activate-service-account 12202776487-compute@developer.gserviceaccount.com --key-file="$GOOGLE_APPLICATION_CREDENTIALS" --project phenomenal-1145

echo -e "----------------------------------\n   $(date)   \n----------------------------------"
del_date=$(date +"%Y-%m-%d" --date="1 days ago")
echo -e "Google Cloud Engine - Looking for old KubeNow's images:\n "

# Extracting both KubeNow images that are flagged as "test" or "current"
gcloud compute images list --filter='Name:kubenow-*-current OR Name:kubenow-*-test' --format=json > /tmp/gce_out_images.json
sed -i '1s/^/{"Images":/' /tmp/gce_out_images.json
sed -i "$ a }" /tmp/gce_out_images.json

tot_no_images=$(grep -c -i "name" < /tmp/gce_out_images.json)

if [ "$tot_no_images" -gt "0" ]; then
    counter_del_img=0
    # Finding Image names of images older than 3 days which needed to be deregistered
    index=0
    while [ "$index" -lt "$tot_no_images" ]; do
        img_date=$(jq ".Images[$index] | .creationTimestamp" /tmp/gce_out_images.json | sed -e 's/^"//' -e 's/"$//' -e 's/T.*//')

        if [ "$img_date" == "$del_date" ]; then
            # Extracting image's "Name"
            name=$(jq ".Images[$index] | .name" /tmp/gce_out_images.json | sed -e 's/^"//' -e 's/"$//')
            echo -e "Following old image dated $img_date is found \nName: $name\n"               

            # Deregistering the AMI
            echo -e "Starting the deletion of image: $name...\n"
            gcloud compute images delete "$name" -q
            counter_del_img=$((counter_del_img+1))
        fi
        index=$((index+1))
    done
    
    if [ "$counter_del_img" == "0" ]; then
        echo -e "No old images dated $del_date were found \n"
    fi
    
else
    echo -e "No GCE KubeNow images flagged as test or current were found"
fi

# Extracting both KubeNow bucket objects that are flagged as "test" or "current"
gsutil ls gs://kubenow-images/ | grep -E 'kubenow-v([0-9]*)([ab0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*).tar.gz([.exporter.log]*)' > /tmp/gce_bk_objs.txt
tot_no_bk_obj=$(wc -l < /tmp/gce_bk_objs.txt)

if [ "$tot_no_bk_obj" -gt "0" ]; then
    counter_del_obj=0
    # Finding Bucket object older than 3 days which needed to be deleted
    echo -e "Looking for old KubeNow's Bucket Objects...\n "
    while read -r line; do
        gsutil ls -l "$line" | awk 'NR==1{print $3, $2}' > /tmp/gce_obj_details.txt
        img_date=$(awk '{print $2}' /tmp/gce_obj_details.txt | sed -e 's/T.*//')

        if [ "$img_date" == "$del_date" ]; then
            # Extracting bkucet object's "name"
            url=$(awk '{print $1}' /tmp/gce_obj_details.txt)
            name=$(awk '{print $1}' /tmp/gce_obj_details.txt | sed 's/gs:\/\/kubenow-images\///g')
            echo -e "\nFollowing old bucket object dated $img_date is found \nName: $name\n"               

            # Deleting Bucket Object
            echo -e "Starting the deletion of bucket object: $name...\n"
            gsutil rm "$url"
            counter_del_obj=$((counter_del_obj+1))
        fi
    done < /tmp/gce_bk_objs.txt
    
    if [ "$counter_del_obj" == "0" ]; then
        echo -e "No old bucket objects dated $del_date were found \n"
    fi
    
else
    echo -e "No GCE KubeNow bucket objects flagged as test or current were found"
fi

echo -e "\nNo of deleted image: $counter_del_img\nNo of deleted bucket object: $counter_del_obj\nDone.\n"
