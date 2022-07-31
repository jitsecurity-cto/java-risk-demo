# Installation

1. Apply the `codebuild` Terraform template in the `Dev` workspace. (We perform the build in the `dev` account because
   we already have very good build infrastructure set up there).
2. Download the `java-risk-demo.jar` file, which was built, into your workstation.
3. Apply the `app` Terraform template in the `demo` workspace. Use `-var app_file=` to specify the path to the JAR
   file you downloaded.
4. Grab the values of the `load_balancer_dns_name` and `lb_zone_id` Terraform outputs. You'll need them later.
5. Apply the `dev-dns` Terraform template. You'll need to provide two variables:
   * `lb_dns`: should be the value of the `load_balancer_dns_name` output from the previous step.
   * `lb_zone_id`: should be the value of the `lb_zone_id` output from the previous step.
6. From 1Password, look for the `Demo: SSL Certificate (java-risk-demo)` entry. Grab the **public** certificate
   and import it into your OS's trusted certificate store as a trusted root CA.

## SSH'ing to the VM

The VM's public DNS name is available via the `ec2-54-197-15-59.compute-1.amazonaws.com` output of the `app`
Terraform template. To SSH, use that DNS name with the username `ubuntu`. You can find the SSH private key file
in 1Password, under `Demo: SSH key (java-risk-demo)`.

Everything you're looking for is in `/home/ubuntu`.
