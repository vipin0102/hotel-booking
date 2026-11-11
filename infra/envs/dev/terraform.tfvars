environment = "dev"
aws_region  = "ap-south-1"
vpc_cidr    = "10.10.0.0/16"
azs         = ["ap-south-1a", "ap-south-1b"]

# ECS - small
container_image = "nginx:alpine"
task_cpu        = 256
task_memory     = 512
desired_count   = 1

# RDS - small, short backups, no deletion protection
db_instance_class        = "db.t4g.micro"
db_allocated_storage     = 20
db_backup_retention_days = 3
db_deletion_protection   = false
db_multi_az              = false
