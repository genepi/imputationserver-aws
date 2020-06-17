# Michigan Imputation Server (MIS) on AWS EMR

This repository includes all required steps to launch a MIS instance on AWS using EMR. 
The official MIS instance provides several state-of-the-art imputation reference-panels and is available at https://imputationserver.sph.umich.edu/.

**Import:** Please always check if you succesfully terminated your AWS EMR cluster by using the Amazon Console. This repository only includes steps to launch a new EMR cluster.

## Requirements
- AWS Command Line Interface (https://aws.amazon.com/cli/) (Ubuntu 18: `pip install awscli`)
- run `aws configure` to set your credentials
  - Set AWS Access Key ID, AWS Secret Access Key, Default region name, Default output format
  - AWS Secret Access Key is not stored on AWS, only available when creating a new Access Key ("Create Access Key")
  - Create a KeyPair for your default region. (See "KeyName" when starting a cluster)
- Access to a S3 bucket including all required files and reference panels (see below)


## Overall Structure
The following folder structure must be available on a S3 bucket to launch a MIS instance. In this example we are using our public bucket `s3://michigan-imputation-aws-public` that is synchronized with the EC2 EMR cluster during setup.  

<pre>
├── apps.yaml
├── bootstrap.sh
├── configuration
│   ├── cloudgene-aws
│   ├── cloudgene.conf
│   ├── config
│   │   └── settings.yaml
│   └── pages
│       ├── contact.stache
│       ├── home.stache
│       └── images
└── reference-panels 

</pre>

### Details `apps.yaml`
``apps.yaml`` includes all currently installed apps and reference panels. By default, the Michigan Imputation Server app (`imputationserver.zip`) and the HapMap2 reference panel are installed. 

```
url: https://github.com/genepi/imputationserver/releases/download/v1.4.0/imputationserver.zip
---
url: s3://michigan-imputation-aws-public/reference-panels/hapmap2
```

### Details `bootstrap.sh`
The ``bootstrap.sh`` script installs all required software packages:

- Installs Cloudgene (https://github.com/genepi/cloudgene)
- Installs Docker (Cloudgene use it to execute R and RMarkdown)
- Sync with `s3://michigan-imputation-aws-public/configuration` to customize Cloudgene (e.g. pages, help, ...)
- Installs all applications listed in apps.yaml 
- Starts `cloudgene-aws` in background, which is located on the S3 bucket (`cloudgene-aws` waits until YARN service is started and starts Cloudgene)

### Details `instance-groups.json`
``instance-groups.json`` contains hardware specifications for all nodes (e.g. number workers, instance type, size of EBS volume)

### Details `emr-config.json`
``emr-config.json`` contains all YARN specific parameters (e.g. task timeout, memory settings, ...). Local file paths need to start with `file://`.

### Details `settings.yaml`
This file includes all required Cloudgene configuration. For a productive setup, we recommend to set an external database (H2 by default) and an S3 location to export final imputation results.

<pre>
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
</pre>

## Sample Configuration
- `clusters/small` describes a small cluster with 1 master, 2 workers, all of them are m4.large instances with 128 GB EBS volume
- `clusters/spot` describes the same setup but adding 6 spot instances (m4.2xlarge) as TASKS with a bid price of 0.2.
  
  
## Start cluster

The following command starts a cluster with provided instance groups and yarn config from folder `spot` and a bootstrap action that installs Cloudgene, Michigan Imputation Server and HapMap2. Ensure that you have access to bucket `s3://michigan-imputation-aws-public` and set your key. If the bucket is private, it needs to be in the same region as the EMR cluster.

When changing the location of the S3 bucket, please also adapt the s3 bucket location in `bootstrap.sh` and `apps.yaml`.  

```
aws emr create-cluster \
    --name Imputationserver \
    --applications Name=Hadoop Name=Ganglia \
    --release-label emr-5.29.0 \
    --use-default-roles \
    --ec2-attributes KeyName=<key-name> \
    --instance-groups file://clusters/spot/instance-groups.json \
    --configuration file://clusters/spot/emr-config.json \
    --bootstrap-actions Path=s3://michigan-imputation-aws-public/bootstrap.sh,Args=[]
```

## Connect to the EC2 instance

The DNS-Name of the Cloudgene instance can be found in property `MasterPublicDnsName` (e.g. ec2-13-59-108-176.us-east-2.compute.amazonaws.com) Cloudgene runs on port **8082** (e.g. http://ec2-13-59-108-176.us-east-2.compute.amazonaws.com:8082).

**Attention**: If you start the cluster for the first time, you need to open port 8082. The security group of the master node can be found in property `EmrManagedMasterSecurityGroup`. Open Amazon Web Console, click on EC2 -> Security Group and configure inboud traffic.

## Submit your fist imputation job

Login as **admin** with the default admin password **admin1978**. You can now start a job by clicking on *Run*. More about submitting jobs and data preparation can be found in our [documentation]


## Monitor your cluster

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
## Known shortcomings
- Sets temp directory in `job.config` to /mnt (mounted EBS volume).
- cloudgene-aws is currently run with sudo permission (required by Docker)
