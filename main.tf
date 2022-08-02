

resource "aws_vpc" "foo" {
  cidr_block = "10.0.0.0/16"

  tags = var.tagsVPC
  
#   tags = {
#     Name = "ECS-EFS-VPC"
#   }
}

resource "aws_subnet" "alpha" {
  vpc_id            =  aws_vpc.foo.id
  availability_zone = "eu-west-1a"
  cidr_block        = "10.0.1.0/24"
  
  tags = {
    Name = "ECS-EFS-SUBNET"
  }
}

resource "aws_subnet" "alpha2" {
  vpc_id            =  aws_vpc.foo.id
  availability_zone = "eu-west-1a"
  cidr_block        = "10.0.2.0/24"
  
  tags = {
    Name = "ECS-EFS-SUBNET2"
  }
}


resource "aws_efs_file_system" "foo" {
    tags = var.tagsMNT
#   tags = {
#     Name = "ECS-EFS-FS"
#   }
}

resource "aws_efs_mount_target" "mount" {
  file_system_id = aws_efs_file_system.foo.id
  subnet_id      = aws_subnet.alpha.id

#   tags = var.tagsMNT

#   tags = {
#     Name = "ECS-EFS-MNT"
#   }
}

// TODO: add security group for EFS Mount Target to allow access only from ECS Service security group

resource "aws_ecs_cluster" "foo" {
  name = "efs-example"

}

resource "aws_ecs_service" "bar" {
  name            = "efs-example-service"
  cluster         = aws_ecs_cluster.foo.id
  task_definition = aws_ecs_task_definition.efs-task.arn
  desired_count   = 2
  launch_type     = "EC2"
  
#   network_configuration {
#     subnets = [aws_subnet.alpha.id, aws_subnet.alpha2.id]
#   }

}

resource "aws_ecs_task_definition" "efs-task" {
  family        = "efs-example-task"

  container_definitions = <<DEFINITION
[
  {
      "memory": 128,
      "portMappings": [
          {
              "hostPort": 80,
              "containerPort": 80,
              "protocol": "tcp"
          }
      ],
      "essential": true,
      "mountPoints": [
          {
              "containerPath": "/usr/share/nginx/html",
              "sourceVolume": "efs-html"
          }
      ],
      "name": "nginx",
      "image": "nginx"
  }
]
DEFINITION

  volume {
    name      = "efs-html"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.foo.id
      root_directory = "/path/to/my/data"
    }
  }
}

// TODO: add security group for ECS Service to allow access to EFS Mount Target security group

# resource "aws_ecs_task_set" "example" {
#   service         = aws_ecs_service.bar.id
#   cluster         = aws_ecs_cluster.foo.id
#   task_definition = aws_ecs_task_definition.efs-task.arn

#   load_balancer {
#     target_group_arn = aws_lb_target_group.example.arn
#     container_name   = "mongo"
#     container_port   = 8080
#   }
# }