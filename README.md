# Installation

I automated this as much as I could.

The Route53 step can't be automated because it's done on a different AWS account.

1. Apply the `codebuild` Terraform template in the `Dev` workspace. (We perform the build in the `dev` account because
   we already have very good build infrastructure set up there).
2. Download the `java-risk-demo.jar` file, which was built, into your workstation.
3. Apply the `app` Terraform template in the `demo` workspace. Use `-var app_file=` to specify the path to the JAR
   file you downloaded.
4. Grab the value of the `load_balancer_dns_name` Terraform output.
5. Switch to the `dev` account, and go to Route53
6. Select `solvo.dev`
7. If a `CNAME` record by the name `java-risk-demo.solvo.dev` doesn't exist, then create it by "Create Record". The
   record's name should be `java-risk-demo.solvo.dev`, and the value should be the value of the
   `load_balancer_dns_name` Terraform output from before.

   Otherwise, update the existing record.

