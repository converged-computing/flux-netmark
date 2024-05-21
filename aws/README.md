# Flux Netmark on AWS

Terraform module to create Amazon Machine Images (AMI) for Flux Framework and AWS.
This used to use packer, but it stopped working so now the build is a bit manual for the AMI.

## Usage

### 1. Build Images

We are basically going to create a VM, twice, for each of hpc6a and hpc7a, at the largest sizes. The prices are typically the same. Then ssh in and run the script. I did this manually since I developed it at the same time I ran it.

- build.sh

We build the following AMIs:

- `ami-0ce1a562c586219e6` for hpc6a, which has flux, efa 1.32.0, and netmark
- 

### Deploy with Terraform

Once you have images, we deploy!

```bash
$ cd tf-hpc6a
```

And then init and build. Note that this will run `init, fmt, validate` and `build` in one command.
They all can be run with `make`:

```bash
$ make
```

You can then shell into any node, and check the status of Flux. I usually grab the instance
name via "Connect" in the portal, but you could likely use the AWS client for this too.

```bash
$ ssh -o 'IdentitiesOnly yes' -i "mykey.pem" ubuntu@ec2-xx-xxx-xx-xxx.compute-1.amazonaws.com
```

#### Check Flux

Check the cluster status, the overlay status, and try running a job:

```bash
$ flux resource list
     STATE NNODES   NCORES    NGPUS NODELIST
      free      2      192        0 i-0c13eb61596ffd5c6,i-0f4fe028d6c3036c0
 allocated      0        0        0 
      down      0        0        0
```
```bash
$ flux run -N 2 hostname
i-0c13eb61596ffd5c6
i-0f4fe028d6c3036c0
```

Let's test netmark

```bash
#  -w warmup
#  -t trials
#  -c send/receive cycles
#  -b message size in bytes
#  -s store trial
flux run -N 1 -n 96 netmark -w 10 -t 20 -c 100 -b 0 -s
flux run -N 2 -n 192 netmark -w 10 -t 20 -c 100 -b 0 -s
```

Yes! You can look at the startup script logs like this if you need to debug.

```bash
$ cat /var/log/cloud-init-output.log
```

Some things we likely want:

- To decrease the size of the base image
- To install oras for artifacts

Next: the same on hpc7a
