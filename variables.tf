variable "tagsVPC" {
    type = map(string)
    default = {
        "Name" = "ECS-EFS-VPC"
    }
}

variable "tagsMNT" {
    type = map(string)
    default = {
        "Name" = "ECS-EFS-MNT"
    }
}