variable "name" {
  type        = string
  default     = "union-gims-dev"
  description = "Name used for ECS cluster resources"
}

variable "region" {
  type        = string
  default     = "ap-northeast-2"
  description = "AWS region name"
}

variable "keycloak-image" {
  type        = string
  default     = ".ecr.ap-northeast-2.amazonaws.com/keycloak:1.0.1"
  description = "Keycloak image including registry"
}

variable "lb-cidr-blocks-in" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks to allow access to the load balancer"
}

variable "vpc-id" {
  type        = string
  default     = "vpc-"
  description = "VPC ID, if empty creates a new VPC"
}

variable "public-subnets" {
  type = list(string)
  default = [
    "subnet-",
    "subnet-"
  ]
  description = "Public subnet IDs, must be defined if vpc-id is provided"
}

variable "private-subnets" {
  type = list(string)
  default = [
    "subnet-",
    "subnet-"
  ]
  description = "Private subnet IDs, must be defined if vpc-id is provided"
}

variable "instance-type" {
  type        = string
  default     = "t3.large"
  description = ""
}

variable "key_name" {
  type        = string
  default     = ""
  description = ""
}

variable "ecs_namespace" {
  type        = string
  default     = ""
  description = ""
}

variable "db-private-subnets" {
  type = list(string)
  default = [
    "subnet-",
    "subnet-",
    "subnet-"
  ]
  description = "DB Private subnet IDs, must be defined if vpc-id is provided"
}

variable "db-name" {
  type        = string
  default     = ""
  description = "Keycloak DB name"
}

variable "db-username" {
  type        = string
  default     = ""
  description = "Keycloak DB username"
}

variable "db-snapshot-identifier" {
  type        = string
  default     = null
  description = "If creating a new DB restore from this snapshot"
}

variable "db-instance-type" {
  type        = string
  default     = "db.t3.micro"
  description = "RDS instance type: https://aws.amazon.com/rds/instance-types/"
}

variable "loadbalancer-certificate-arn" {
  type        = string
  default     = ""
  description = "ARN of the ACM certificate to use for the load balancer"
}

variable "keycloak-hostname" {
  type        = string
  default     = ""
  description = "Keycloak hostname, if empty uses the load-balancer hostname"
}

variable "keycloak-loglevel" {
  type        = string
  default     = "INFO"
  description = "Keycloak log-level e.g. DEBUG."
}

variable "desired-count" {
  type        = number
  description = "Number of Keycloak containers to run, set to 0 for DB maintenance"
  default     = 1
}

variable "cpu_target_tracking_desired_value" {
  type        = number
  description = "Number of Keycloak containers to run, set to 0 for DB maintenance"
  default     = 75
}

variable "memory_target_tracking_desired_value" {
  type        = number
  description = "Number of Keycloak containers to run, set to 0 for DB maintenance"
  default     = 75
}

variable "default-tags" {
  type = map(any)
  default = {
    Proj = ""
  }
  description = "Default AWS tags to apply to all resources"
}
