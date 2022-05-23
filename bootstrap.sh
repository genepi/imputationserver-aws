#!/bin/bash

# logging for any errors during bootstrapping
#exec > >(tee -i /var/log/bootstrap-script.log)
#exec 2>&1

# Force the cluster to terminate early with "Bootstrap failure"
# if any command or pipeline returns non-zero exit status.
#set -eo pipefail

# Check for master node
IS_MASTER=true
if [ -f /mnt/var/lib/info/instance.json ]
then
    IS_MASTER=$(jq .isMaster /mnt/var/lib/info/instance.json)
fi

# Continue only if master node
if [ "$IS_MASTER" = false ]; then
    exit
fi



cd /home/hadoop


## Install and setup Cloudgene
curl -s install.cloudgene.io | bash -s 2.5.1

## Install and setup Docker
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker hadoop

## Customize Cloudgene installation
aws s3 sync s3://michigan-imputation-aws-public/configuration .
chmod +x cloudgene-aws

## Install imputationserver and reference panels
./cloudgene clone s3://michigan-imputation-aws-public/apps.yaml

## set tmp-directory to ebs volume. Warning: Hardcoded path with version! Adapt it on update!
echo "minimac.tmp=/mnt/mapred" > "/mnt/apps/imputationserver/1.6.7/job.config"
echo "chunksize=10000000" >> "/mnt/apps/imputationserver/1.6.7/job.config"

## Start webservice on port 8082. Needs sudo to avoid permission issues with docker.
sudo ./cloudgene-aws &
