variable "access_key" {
  type    = string
}

variable "secret_key" {
  type    = string
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  description = "Your new project name"
}

variable "domain_name" {
  type    = string
  description = "Your Route 53 domain"
}

variable "postgres_username" {
  type        = string
  description = "The master username for Postgres"
}

variable "postgres_password" {
  type        = string
  description = "The master password for Postgres"
}

variable "api_token" {
  type        = string
  description = "The API token for the schema server"
}

variable "jwt_secret" {
  type        = string
  description = "The JWT secret for Postgrest"
}
