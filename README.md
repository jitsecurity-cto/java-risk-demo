# Installation

1. Apply the `codebuild` Terraform template in the `Dev` workspace. (We perform the build in the `dev` account because
   we already have very good build infrastructure set up there).
2. Download the `app.war` file, which was built, into your workstation.
3. Apply the `app` Terraform template in the `demo` workspace. Use `-var app_file=` to specify the path to the JAR
   file you downloaded.
4. Grab the values of the Terraform outputs. You'll need them later. (Use `terraform output` to show them again)
5. Save the contents of the `public_cert` output into a file, and add it to your OS's trusted certificate store.
5. Apply the `dev-dns` Terraform template. You'll need to provide two variables:
   * `lb_dns`: should be the value of the `load_balancer_dns_name` output from the previous step.
   * `lb_zone_id`: should be the value of the `lb_zone_id` output from the previous step.
7. Trigger the AWS Inspector run. Grab the value of the `assessment_arn` output from the `app` template, and use
   the following AWS CLI command:
   ```bash
   aws inspector start-assessment-run --assessment-template-arn <template-arn-from-output>
   ```

## SSH'ing to the VM

The VM's public DNS name is available via the `vm_public_dns` output of the `app`
Terraform template. To SSH, use that DNS name with the username `ubuntu`. You can find the SSH private key file
in 1Password, under `Demo: SSH key (java-risk-demo)`.

Everything you're looking for is in `/home/ubuntu`.
