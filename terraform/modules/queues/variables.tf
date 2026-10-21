variable "name_prefix" {
  description = "Resource name prefix."
  type        = string
}

variable "visibility_timeout" {
  description = "Seconds a message is hidden after being received."
  type        = number
}

variable "max_receive_count" {
  description = "Failed receives before a message moves to the DLQ."
  type        = number
}

variable "tags" {
  description = "Additional tags to merge onto all resources."
  type        = map(string)
  default     = {}
}
