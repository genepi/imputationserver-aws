# Michigan Imputation Server (MIS) on AWS EMR

This repository includes all required steps to launch a MIS instance on Amazon AWS. 

## Requirements
- AWS Command Line Interface (https://aws.amazon.com/cli/) (Ubuntu 18: `pip install awscli`)
- run `aws configure` to set your credentials under 'My security credentials'
  - Set AWS Access Key ID, AWS Secret Access Key, Default region name, Default output format
  - AWS Secret Access Key is not stored on AWS, only available when creating a new Access Key ("Create Access Key")
  - Use `us-east-2` as a default region or create a new KeyPair for other regions. (See "KeyName" when starting a cluster)


## Configuration files
- To define a cluster we need two json files:
  - `instance-groups.json` contains hardware specifications for nodes (e.g. number workers, instance type, size of EBS volume)
  - `emr-config.json` contains all YARN specific parameters (e.g. task timeout, memory settings, ...)
  - Local File Paths need to start with `file://`

## Example configuration for evaluation
- `clusters/small` describes a small cluster with 1 master, 2 workers, all of them are m4.large instances with 128 GB EBS volume
- `clusters/spot` describes the same setup but adding spot instances as TASKS with a bid price of 2.

## Start cluster

Starts a cluster with provided instance groups and yarn config from folder `small` and a bootstrap action that installs Cloudgene, Imputationserver and HapMap. Ensure that you have access to bucket `s3://imputationserver-aws`.

```
aws emr create-cluster \
    --name Imputationserver \
    --applications Name=Hadoop Name=Ganglia \
    --release-label emr-5.26.0 \
    --use-default-roles \
    --ec2-attributes KeyName=imputation \
    --instance-groups file://clusters/small/instance-groups.json \
    --configuration file://clusters/small/emr-config.json \
    --bootstrap-actions Path=s3://imputationserver-aws/bootstrap.sh,Args=[]
```

After submitting, you get a cluster id `j-XXXXXXXXXX`. Use this id to check the state of the cluster:

```
aws emr describe-cluster --cluster-id j-XXXXXXXXXX
```
You can also use the AWS Console under `EMR` to see the current status.

Cluster is ready after several minutes and you should see `"State": "WAITING"`:

```
"Cluster": {
    "Status": {
        "Timeline": {
            "ReadyDateTime": 1563957041.697,
            "CreationDateTime": 1563956816.758
        },
        "State": "WAITING",
        "StateChangeReason": {
            "Message": "Cluster ready to run steps."
        }
    },
...
}
```

The DNS-Name of the cloudgene instance can be found in property `MasterPublicDnsName` (e.g. ec2-13-59-108-176.us-east-2.compute.amazonaws.com) Cloudgene runs on port 8082 (e.g. http://ec2-13-59-108-176.us-east-2.compute.amazonaws.com:8082).

**Attention**: If you start the cluster for the first time, you need to open port 8082. The security group of the master node can be found in property `EmrManagedMasterSecurityGroup`. Open Amazon Web Console, click on EC2 -> Security Group and configure inboud traffic.

## Details `bootstrap.sh`

- Installs Cloudgene
- Installs Docker (Cloudgene use it to execute R and RMarkdown)
- sync with s3://imputationserver/configuration to customize Cloudgene (e.g. pages, help, ...)
- Installs all applications listed in s3://imputationserver/apps.yaml (Private reference panels can be hosted on a private s3 bucket)
- Workaround: Sets temp directory in `job.config` to /mnt (mounted EBS volume)
- Starts `cloudgene-aws` in background (`cloudgene-aws` waits until YARN service is started and starts Cloudgene)
