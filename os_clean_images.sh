#!/bin/bash
# Script to delete Openstack private images older than n no of days

# Exit immediately if a command exits with a non-zero status
set -e

# Fix OS potential issue/bug: "sudo: unable to resolve host..."
sudo sed -i /etc/hosts -e "s/^127.0.0.1 localhost$/127.0.0.1 localhost $(hostname)/"

# Installing necessary tool for the script: awscli and jq
sudo apt-get update && sudo apt-get install python-dev python-pip -y
pip install --upgrade pip
sudo pip install python-glanceclient

echo -e "----------------------------------\n   $(date)   \n----------------------------------"
del_date=$(date +"%Y-%m-%d" --date="1 days ago")
echo "del_date: $del_date"
echo -e "Openstack - Looking for old KubewNow images:\n "

# Extracting both KubeNow images that are flagged as "test" or "current"
glance image-list | grep -E 'kubenow-v([0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*)' | awk '{print $2, $4}' > /tmp/os_out_images.txt
tot_no_images=$(wc -l < /tmp/os_out_images.txt)

if [ "$tot_no_images" -gt "0" ]; then
    counter_del_img=0
    # Finding Image IDs of AMIs older than 3 days which needed to be deregistered
    while read -r line; do
        glance image-show "$(echo "$line" | awk '{print $1}')" > /tmp/os_img_details.txt
        img_date=$(grep -i "created_at" < /tmp/os_img_details.txt | awk '{print $4}' | sed -e 's/T.*//')

        if [ "$img_date" == "$del_date" ]; then
            # Extracting image's "Name" and "ImageId"
            id_to_delete=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            echo -e "Following old images dated $img_date is found \nName: $name \nID:$id_to_delete"           

            # Deleting old KubeNow Image
            printf "Starting to delete KubewNow image: %s...\n\n" "$id_to_delete"
            glance image-delete $id_to_delete
            counter_del_img=$((counter_del_img+1))
            echo -e "Keep looking for any other old KubeNow images...\n"
        fi
    done < /tmp/os_out_images.txt
    
    if [ "$counter_del_img" == "0" ]; then
        echo -e "No old images dated $del_date were found \n"
    fi
    
else
    echo -e "No KubeNow iamges flagged as test or current were found"
fi

echo -e "\nNo of deleted image: $counter_del_img\nDone.\n"
