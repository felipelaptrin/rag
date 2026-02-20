## Bootstrap Lambda
This is a dummy Python code that is used to deploy a Docker image to ECR.

### Goal
The main goal of this folder is to avoid the chicken and the egg problem when deploying an ECR repository and a Lambda code (that points to an image in this ECR repository) on the first run.

### The problem
If you try to deploy:
- ECR Repository
- Lambda Function (that points to an image in this ECR repository)
On the first `terraform apply`, you will get an error since the brand new ECR repository will be empty and the lambda will reference an image tag that has not been pushed.

## The fix
To fix this problem and allow a successful deployment, the Terraform code will be responsible for pushing dummy code with the tag `bootstrap`. This tag will be used and referenced in the `aws_lambda_function` resource, but Terraform will not manage the code deployment of the Lambda, since this will be the responsibility of the Lambda Git Repository CI/CD.

The runner that runs Terraform (i.e., CI/CD) needs to have `Docker` installed (which is a common requirement in CI/CD runners) in order to build, tag, and push this dummy image to the repository. Please note that this process only happens once, and this step is considered to be a `bootstrap` of the ECR Repository.
