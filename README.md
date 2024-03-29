# snowclone-terra
infrastructure provisioning

- Create a .tfvars file in /instance and include the following: 

```
access_key        = <ACCESS_KEY>
secret_key        = <SECRET_KEY>
region            = <REGION>
project_name      = <PROJECT_NAME>
domain_name       = <DOMAIN_NAME>
postgres_username = <USERNAME> (cannot be admin)
postgres_password = <PASSWORD> (must be at least 8 characters)
api_token         = <REGION> 
jwt_secret        = <REGION> (must be 32 characters)
```

- You must have a Route53 Domain registered in your AWS Account.
- Run the apply with `terraform apply -var-file=example.tfvars`
- Run the following curl request `curl -H "Authorization: Bearer <API_TOKEN>" -F 'file=@apiSchema.sql' https://<PROJECT_NAME>.<DOMAIN_NAME>/schema` to get the Postgrest service to run healthy

(Contents of apiSchema.sql can be found in main repo.)
