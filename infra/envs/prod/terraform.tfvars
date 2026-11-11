environment = "prod"
aws_region  = "ap-south-1"
vpc_cidr    = "10.20.0.0/16"
azs         = ["ap-south-1a", "ap-south-1b"]

# ECS - larger
container_image = "nginx:alpine"
task_cpu        = 512
task_memory     = 1024
desired_count   = 2

# RDS - larger, long backups, deletion protection ON
db_instance_class        = "db.t4g.medium"
db_allocated_storage     = 50
db_backup_retention_days = 14
db_deletion_protection   = true
db_multi_az              = true
