terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-west-1"
}

resource "aws_vpc" "custom_vpc" {
  cidr_block           = var.custom_vpc
  instance_tenancy     = var.instance_tenancy
  enable_dns_support   = true
  enable_dns_hostnames = true

}

resource "aws_subnet" "public_subnet" {
  count             = var.custom_vpc == "10.0.0.0/16" ? 2 : 0
  vpc_id            = aws_vpc.custom_vpc.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = element(cidrsubnets(var.custom_vpc, 8, 4, 4), count.index)

  tags = {
    "Name" = "Public-Subnet-${count.index}"
  }
}


resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    "Name" = "Internet-Gateway"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    "Name" = "Public-RouteTable"
  }
}

resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_rt_association" {
  count          = length(aws_subnet.public_subnet) == 2 ? 2 : 0
  route_table_id = aws_route_table.public_rt.id
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
}

# resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
#   name              = "VPC-FlowLogs-Group"
#   retention_in_days = 30
# }

# resource "aws_flow_log" "vpc_flow_log" {
#   iam_role_arn         = data.aws_iam_role.iam_role.arn
#   log_destination_type = "cloud-watch-logs"
#   log_destination      = aws_cloudwatch_log_group.cloudwatch_log_group.arn
#   traffic_type         = "ALL"
#   vpc_id               = aws_vpc.custom_vpc.id
# }

locals {
  ingress_rules = [{
    name        = "HTTPS"
    port        = 443
    description = "Ingress rules for port 443"
    },
    {
      name        = "HTTP"
      port        = 80
      description = "Ingress rules for port 80"
    },
    {
      name        = "SSH"
      port        = 22
      description = "Ingress rules for port 22"
  }]

}

resource "aws_security_group" "sg" {

  name        = "CustomSG"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.custom_vpc.id
  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  dynamic "ingress" {
    for_each = local.ingress_rules

    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = {
    Name = "AWS security group dynamic block"
  }

}

resource "aws_security_group" "ec2_security_group" {
name        = "ec2_security_group"
description = "Allow SSH and HTTP"
vpc_id      = aws_vpc.custom_vpc.id
ingress {
description = "SSH from VPC"
from_port   = 22
to_port     = 22
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
description = "EFS mount target"
from_port   = 2049
to_port     = 2049
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
description = "HTTP from VPC"
from_port   = 80
to_port     = 80
protocol    = "tcp"
cidr_blocks = ["0.0.0.0/0"]
  }
egress {
from_port   = 0
to_port     = 0
protocol    = "-1"
cidr_blocks = ["0.0.0.0/0"]
  }
}



#   timeouts {
#     create = "10m"
#   }

# }

# resource "null_resource" "null" {
#   count = length(aws_subnet.public_subnet.*.id)

#   provisioner "file" {
#     source      = "./userdata.sh"
#     destination = "/home/ec2-user/userdata.sh"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "chmod +x /home/ec2-user/userdata.sh",
#       "sh /home/ec2-user/userdata.sh",
#     ]
#     on_failure = continue
#   }

#   connection {
#     type        = "ssh"
#     user        = "ec2-user"
#     port        = "22"
#     host        = element(aws_eip.eip.*.public_ip, count.index)
#     # private_key = file(var.ssh_private_key)

# }


# resource "aws_eip" "eip" {
#   count            = length(aws_instance.instance.*.id)
#   instance         = element(aws_instance.instance.*.id, count.index)
#   public_ipv4_pool = "amazon"
#   vpc              = true

#   tags = {
#     "Name" = "EIP-${count.index}"
#   }
# }

# resource "aws_eip_association" "eip_association" {
#   count         = length(aws_eip.eip)
#   instance_id   = element(aws_instance.instance.*.id, count.index)
#   allocation_id = element(aws_eip.eip.*.id, count.index)
# }

# Creating EFS file system
resource "aws_efs_file_system" "efs" {
creation_token = "my-efs"
tags = {
Name = "MyProduct"
  }
}

# Generate new private key
resource "tls_private_key" "my_key" {
algorithm = "RSA"
}
# Generate a key-pair with above key
resource "aws_key_pair" "deployer" {
key_name   = "efs-key"
public_key = tls_private_key.my_key.public_key_openssh
}
# Saving Key Pair for ssh login for Client if needed
resource "null_resource" "save_key_pair"  {
provisioner "local-exec" {
command = "echo  ${tls_private_key.my_key.private_key_pem} > mykey.pem"
}
}

resource "aws_db_instance" "MySQL" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  name                 = "mydb"
  username             = "user"
  password             = "admin1234"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
  vpc_security_group_ids = [aws_security_group.sg.id, aws_security_group.ec2_security_group.id]
}


resource "aws_instance" "instance" {
  count                = length(aws_subnet.public_subnet.*.id)
  ami                  = var.ami_id
  instance_type        = var.instance_type
  subnet_id            = element(aws_subnet.public_subnet.*.id, count.index)
  security_groups      = [aws_security_group.sg.id, aws_security_group.ec2_security_group.id]
  key_name             = "${file("mykey.pem")}" #"efs-key" 
#   iam_instance_profile = data.aws_iam_role.iam_role.name

  tags = {
    "Name"        = "Instance-${count.index}"
    "Environment" = "Test"
    "CreatedBy"   = "Terraform"
  }


 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.my_key.private_key_pem}"
    host     = self.private_ip
  }

  provisioner "remote-exec" {
inline = [
"sudo yum install httpd php git -y -q ",
"sudo systemctl start httpd",
"sudo systemctl enable httpd",
"sudo yum install nfs-utils -y -q ", # Amazon ami has pre installed nfs utils
# Mounting Efs 
"sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport ${aws_efs_file_system.efs.dns_name}:/  /var/www/html",
# Making Mount Permanent
"echo ${aws_efs_file_system.efs.dns_name}:/ /var/www/html nfs4 defaults,_netdev 0 0  | sudo cat >> /etc/fstab " ,
"sudo chmod go+rw /var/www/html",
"sudo git clone https://github.com/Apeksh742/EC2_instance_with_terraform.git /var/www/html",
  ]
 }
}

# Creating Mount target of EFS
resource "aws_efs_mount_target" "mount1" {
file_system_id = aws_efs_file_system.efs.id
subnet_id      =  aws_instance.instance[0].subnet_id
security_groups = [aws_security_group.ec2_security_group.id]
}

# Creating Mount Point for EFS
resource "null_resource" "configure_nfs" {
depends_on = [aws_efs_mount_target.mount1]
connection {
type     = "ssh"
user     = "ec2-user"
private_key = tls_private_key.my_key.private_key_pem
host     = aws_instance.instance.public_ip
 }
}
data "aws_availability_zones" "azs" {}

resource "aws_lb_target_group" "tg" {
  name        = "TargetGroup"
  port        = 80
  target_type = "instance"
  protocol    = "HTTP"
  vpc_id      = aws_vpc.custom_vpc.id
}

resource "aws_alb_target_group_attachment" "tgattachment" {
  count            = length(aws_instance.instance.*.id) == 2 ? 2 : 0
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = element(aws_instance.instance.*.id, count.index)
}

resource "aws_lb" "lb" {
  name               = "ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.sg.id]
  subnets            = aws_subnet.public_subnet.*.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn

  }

  condition {
    path_pattern {
      values = ["/var/www/html/index.html"]
    }
  }
}






