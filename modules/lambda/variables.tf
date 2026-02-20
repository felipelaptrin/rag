variable "name" {
  description = "Name of the Lambda Function"
  type        = string
}

variable "description" {
  description = "Description of the lambda"
  type        = string
}

variable "architecture" {
  description = "Architecture of the Lambda. Valid values: x86_64, arm64"
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Valid values for variable 'architecture' are: x86_64, arm64"
  }
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime. Valid value between 128 MB to 32,768 MB (32 GB), in 1 MB increments"
  type        = number
  default     = 512
}

variable "timeout" {
  description = "Amount of time your Lambda Function has to run in seconds"
  type        = number
  default     = 60
}

variable "environment_variables" {
  description = "A map that defines environment variables for the Lambda Function."
  type        = map(string)
  default     = {}
}

variable "log_group_retention_in_days" {
  description = " Specifies the number of days you want to retain log events in the specified log group. Possible values are: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653, and 0. If you select 0, the events in the log group are always retained and never expire."
  type        = number
  default     = 365
}

variable "json_policy" {
  description = "The JSON for the IAM policy of the Lambda"
  type        = string
  default     = null
}
