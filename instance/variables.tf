
variable "project_name" {
  type    = string
  description = "Your new project name"
}

variable "private_subnet_a_id" {
  type        = string
  description = "The id for private subnet a"
}

variable "private_subnet_b_id" {
  type        = string
  description = "The id for private subnet b"
}

variable "postgres_username" {
  type        = string
  description = "The master username for Postgres"
}

variable "postgres_password" {
  type        = string
  description = "The master password for Postgres"
}

variable "domain_name" {
  type        = string
}

variable "region" {
  type        = string

}
variable "api_token" {
  type        = string
  description = "The API token for the schema server"
}

variable "jwt_secret" {
  type        = string
  description = "The JWT secret for Postgrest"
}

variable "aws_route53_zone_id" {
  type = string
}

# data "aws_route53_zone" "zone" {
#   zone_id = "Z0294568BLGUMPVHMAQS"