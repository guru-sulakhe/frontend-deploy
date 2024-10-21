variable "project_name" {
    default = "expense"
}
variable "environment" {
    default = "dev"
}
variable "common_tags" {
    default = {
        Project = "expense"
        Terraform = "true"
        Enviroment = "dev"
        Component = "frontend"
    }
}
variable "zone_name" {
    default = "guru97s.cloud"
}

# created this as a part of CD(continuos deployment)
variable "app_version" {
    
}