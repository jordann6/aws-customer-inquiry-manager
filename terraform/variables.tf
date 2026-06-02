variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment label (dev / prod)."
  type        = string
  default     = "dev"
}

variable "support_email" {
  description = "Email address that receives new inquiry notifications."
  type        = string
}

variable "sender_email" {
  description = "Verified SES sender address used as the From: address."
  type        = string
}
