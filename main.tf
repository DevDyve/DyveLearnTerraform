# Configuring Terraform to use AWS

provider "aws" {
    region = "us-east-2"
}


#Declare resources
resource "aws_instance" "example" {
  ami = "ami-0aeb7c931a5a61206"
  instance_type = "t2.micro"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

# Deploying a Hello World web server cluster
resource "aws_launch_configuration" "example" {
  image_id = "ami-0aeb7c931a5a61206"
  instance_type = "t2.micro"
  security_groups = [ aws_security_group.instance.id ]
  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p ${var.server_port} &
              EOF
    lifecycle {
      create_before_destroy = true
    }
  }



# Creating ASG
resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnet_ids.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}

# Create security group to allow traffic on 8080
resource "aws_security_group" "instance" {
  name = "terraform-example-instance"

    ingress {
      cidr_blocks = [ "0.0.0.0/0" ]
      from_port = var.server_port
      protocol = "tcp"
      to_port = var.server_port
    }
}


# Define a variable
variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}


# Provide DNS as output variable
output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "Thedomain name of the load balancer"
}


# Defining a load balancer
resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.default.ids
  security_groups = [aws_security_group.alb.id]
}

# Defining a listener

resource "aws_lb_listener" "HTTP" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP"
  
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

# Define load balancer security group

resource "aws_security_group" "alb" {
  name = "terraform-example_alb"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
}


# Target group for ASG

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = 80
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}


# Creating a listener rule

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.HTTP.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}
