# snowclone-terra
infrastructure provisioning

create a variables.tf file in snoke and include the following: 

variable "region" {
  type    = string
  default = <AWS_REGION>
}

variable "project_name" {
    type = string
    default = <YOUR_PROJECT_NAME>
}

variable "domain_name" {
    type = string
    default = <YOUR_DOMAIN_NAME>
}

You must have a Route53 Domain registered in your AWS Account.

In order for the Postgrest service to run, you need to send a curl request with the apiSchema.sql file as follows
`curl -H "Authorization: Bearer <API_TOKEN>" -F 'file=@apiSchema.sql' https://<PROJECT_NAME>.<DOMAIN_NAME>/schema` 

(Contents of apiSchema.sql can be found in main repo.)