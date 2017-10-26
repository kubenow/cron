#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Installing Azure command-line client
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | \
     sudo tee /etc/apt/sources.list.d/azure-cli.list

sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893

sudo apt-get update && sudo apt-get install apt-transport-https azure-cli -y

echo -e "----------------------------------\n   $(date)   \n----------------------------------"
del_date=$(date +"%Y-%m-%d" --date="1 days ago")
echo -e "Azure - Looking for old KubewNow images:\n "

# Performing authentication in Azure
az login --service-principal -u "$AZURE_CLIENT_ID" -p "$AZURE_CLIENT_SECRET" --tenant "$AZURE_TENANT_ID" --output "table"

# Extracting both KubeNow images that are flagged as "test" or "current"
az storage blob list --account-name "$AZURE_STORAGE_ACCOUNT" --container-name "$AZURE_CONTAINER_NAME" --query [].name --output tsv | grep -E 'kubenow-v([0-9]*)(a?b?)([0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*)' | grep '.vhd' | tee /tmp/az_out_images.txt

tot_no_images=$(wc -l < /tmp/az_out_images.txt)
counter_del_img=0

if [ "$tot_no_images" -gt "0" ]; then
    
    # Finding Image IDs older than 1 day which needed to be deleted
    while read -r line; do
        img_date=$(az storage blob show --account-name "$AZURE_STORAGE_ACCOUNT" -c "$AZURE_CONTAINER_NAME" -n "$line" -o table | awk 'NR == 3 {print $5}' | sed -e 's/T.*//')

        if [[ ! "$img_date" > "$del_date" ]]; then
            # Extracting image's "Name" and related blob json
            name=$(echo "$line" | grep -E -o 'kubenow-v([0-9]*)(a?b?)([0-9]*)-([0-9]*)-([a-z0-9]*)-([test]*)([current]*)')
            
            # Because of files' names convention between a vhd file and its related vmTemplate json
            rel_json_blob="${line/osDisk/vmTemplate}"
            rel_json_blob="${rel_json_blob/.vhd/.json}"

            echo -e "Following old image dated $img_date is found \nName: $name \n"         

            # Deleting old KubeNow Image
            echo -e "Starting to delete old KubewNow image: $name...\n\n"
            az storage blob delete --account-name "$AZURE_STORAGE_ACCOUNT" -c "$AZURE_CONTAINER_NAME" -n "$line"
            
            # If related json blob does not exist, then will simply skip this step. Otherwise it must be deleted as well
            if [ -n "$rel_json_blob" ]; then
                az storage blob delete --account-name "$AZURE_STORAGE_ACCOUNT" -c "$AZURE_CONTAINER_NAME" -n "$rel_json_blob"
            fi

            counter_del_img=$((counter_del_img+1))
            echo -e "Keep looking for any other old KubeNow image...\n"
        fi
    done < /tmp/az_out_images.txt
    
    if [ "$counter_del_img" == "0" ]; then
        echo -e "No old images dated $del_date were found \n"
    fi
    
else
    echo -e "No KubeNow iamges flagged as test or current were found"
fi

echo -e "\nNo of deleted image: $counter_del_img\nDone.\n"