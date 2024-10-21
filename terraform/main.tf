module "frontend" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  instance_type          = "t2.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]
  # convert StringList to string and get first element
  subnet_id              = local.public_subnet_id # selecting one public subnet from the list
  ami = data.aws_ami.ami_info.id
  tags = merge(
    var.common_tags,
    {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    }
  )

}


# configuring backend server
resource "null_resource" "frontend" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }

     connection {
        type     = "ssh"
        user     = "ec2-user"
        password = "DevOps321"
        host     = module.frontend.private_ip
    }

    provisioner "file" {
        source      = "${var.common_tags.Component}.sh"
        destination = "/tmp/${var.common_tags.Component}.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/${var.common_tags.Component}.sh",
            "sudo sh /tmp/${var.common_tags.Component}.sh ${var.common_tags.Component} ${var.environment} ${var.app_version}"
        ]
    } 
}

# stopping the running server 
resource "aws_ec2_instance_state" "frontend" {
  instance_id = module.frontend.id
  state       = "stopped"
 # stop the server when null resource provisioning is completed
  depends_on = [null_resource.frontend]
}

# capturing AMI from stopped server
resource "aws_ami_from_instance" "frontend" {
  name               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  source_instance_id = module.frontend.id
  depends_on = [aws_ec2_instance_state.frontend]
}

# deleting the backend server after capturing AMI
resource "null_resource" "frontend_delete" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }

    provisioner "local-exec" {
        command = "aws ec2 terminate-instances --instance-ids ${module.frontend.id}"
    }
    depends_on = [aws_ami_from_instance.frontend] 
}

# creating target group 
resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value

    health_check { # checking for 2 times under port whether the target grooup is healthy threshold or unhealthy threshold
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

# creating launch template based on the AMI image ID
resource "aws_launch_template" "frontend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  image_id = aws_ami_from_instance.frontend.id

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"
  update_default_version = true # sets the latest version to default

  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.common_tags,
      {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
      }
    )
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  max_size                  = 5 # 5 instances
  min_size                  = 1 # 1 instance
  health_check_grace_period = 60 # 60 seconds
  health_check_type         = "ELB"
  desired_capacity          = 1 # 1 instance
  target_group_arns = [aws_lb_target_group.frontend.arn] # deploying  backend instance into target group
    launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

    instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "lorem"
    value               = "ipsum"
    propagate_at_launch = false
  }
}

# Adding autoscaling group policy
# Based on the policy the auto scaling will generate new instances (e.g AVERAGECPUUTILIZATION) 
resource "aws_autoscaling_policy" "frontend" {
  name                   = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name

    target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 10.0
  }
}
# Adding listner in frontend load balancer
# at which whenever user will enter https://frontend.web-dev.guru97s.cloud it will be sended to the frontend target group servers
resource "aws_lb_listener_rule" "frontend" {
  listener_arn = data.aws_ssm_parameter.web_alb_listener_arn_https.value
  priority     = 100 # less number will be validated first

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = ["web-${var.environment}.${var.zone_name}"] # web-dev.guru97s.cloud
    }
  }
}