# Michigan Imputation Server (MIS) on AWS EMR

This repository includes all required steps to launch a MIS instance on AWS using EMR. The MIS instance hosting several state-of-the-art panels is available at https://imputationserver.sph.umich.edu/.

**Import:** Please always check if you succesfully terminated your AWS EMR cluster by using the Amazon Console. This repository only includes step to launch a new cluster.

## Requirements
- AWS Command Line Interface (https://aws.amazon.com/cli/) (Ubuntu 18: `pip install awscli`)
- run `aws configure` to set your credentials
  - Set AWS Access Key ID, AWS Secret Access Key, Default region name, Default output format
  - AWS Secret Access Key is not stored on AWS, only available when creating a new Access Key ("Create Access Key")
  - Create a KeyPair for your default region. (See "KeyName" when starting a cluster)


## Overall Structure
Files marked in bold are located on our public S3 bucket `s3://michigan-imputation-aws` and are synchronized with the EC2 EMR cluster when during setup.  

<pre>
├── <b>apps.yaml</b>
├── <b>bootstrap.sh</b>
├── clusters
│   ├── small
│   │   ├── <b>emr-config.json</b>
│   │   └── <b>instance-groups.json</b>
│   └── spot
│       ├── emr-config.json
│       └── instance-groups.json
├── configuration
│   └── config
│       └── <b>settings.yaml</b>
└── README.md

</pre>

### Details ``apps.yaml``
``apps.yaml`` includes all currently installed apps and reference panels. By default, the Michigan Imputation Server app (``imputationserver.zip``) and the HapMap2 reference panel are installed. 

```
url: https://github.com/genepi/imputationserver/releases/download/v1.4.0/imputationserver.zip
---
url: s3://michigan-imputation-aws/reference-panels/hapmap2
```

### Details ``bootstrap.sh``
The ``bootstrap.sh`` script installs all required software packages:

- Installs Cloudgene (https://github.com/genepi/cloudgene)
- Installs Docker (Cloudgene use it to execute R and RMarkdown)
- Sync with s3://michigan-imputation-aws/configuration to customize Cloudgene (e.g. pages, help, ...)
- Installs all applications listed in apps.yaml 
- Starts `cloudgene-aws` in background (`cloudgene-aws` waits until YARN service is started and starts Cloudgene)

### Details ``emr-config.json``
``instance-groups.json`` contains hardware specifications for all nodes (e.g. number workers, instance type, size of EBS volume)

### Details ``instance-groups.json``
``emr-config.json`` contains all YARN specific parameters (e.g. task timeout, memory settings, ...). Local file paths need to start with `file://`.

### Details ``settings.yaml``
This file includes all required Cloudgene configuration. For a productive setup, we recommend to set an external database (H2 by default) and an S3 location to export final results.
``
externalWorkspace:
   type: s3
   location: <s3://s3-bucket>
database:
   database: <name>
   password: <password>
   driver: mysql
   port: 3306
   host: <host>
   user: <user>
``

## Sample Configuration
- `clusters/small` describes a small cluster with 1 master, 2 workers, all of them are m4.large instances with 128 GB EBS volume
- `clusters/spot` describes the same setup but adding spot instances as TASKS with a bid price of 2.
  
  
## Start cluster

The following command starts a cluster with provided instance groups and yarn config from folder `small` and a bootstrap action that installs Cloudgene, Imputationserver and HapMap. Ensure that you have access to bucket `s3://imputationserver-aws`.

```
aws emr create-cluster \
    --name Imputationserver \
    --applications Name=Hadoop Name=Ganglia \
    --release-label emr-5.29.0 \
    --use-default-roles \
    --ec2-attributes KeyName=<key-name> \
    --instance-groups file://clusters/spot/instance-groups.json \
    --configuration file://clusters/spot/emr-config.json \
    --bootstrap-actions Path=s3://michigan-imputation-aws/bootstrap.sh,Args=[]
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
## Connect to the EC2 instance

The DNS-Name of the Cloudgene instance can be found in property `MasterPublicDnsName` (e.g. ec2-13-59-108-176.us-east-2.compute.amazonaws.com) Cloudgene runs on port **8082** (e.g. http://ec2-13-59-108-176.us-east-2.compute.amazonaws.com:8082).

**Attention**: If you start the cluster for the first time, you need to open port 8082. The security group of the master node can be found in property `EmrManagedMasterSecurityGroup`. Open Amazon Web Console, click on EC2 -> Security Group and configure inboud traffic.


## Current shortcomings
- Sets temp directory in `job.config` to /mnt (mounted EBS volume).
- cloudgene-aws is started with sudo permission since this is required by Docker.
