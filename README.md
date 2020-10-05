# TF Lambda + API gateway example

This project is an example of using Terraform to deploy a simple web page which reaches out to a lambda function.

## How to run

* Set your local AWS environment variables:
```shell script
export AWS_ACCESS_KEY_ID="XXXXXXXXXXXXXXXX"
export AWS_SECRET_ACCESS_KEY="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
```
* Update the `terraform/variables.tf` file to use your desired bucket name (or pass in via an environment variable).
* `terraform init` to pull the necessary dependencies
* `terraform apply` to run the terraform operations
* Check the output for the s3 bucket url

## Possible improvements
* An authorizer using cognito or a lambda could ensure the backend lambda isn't open to the world.
* Setting up MFA for the api would allow for the MFA-delete options on the s3 buckets
* Figure out a better way to embed the API gateway URL into the frontend javascript
