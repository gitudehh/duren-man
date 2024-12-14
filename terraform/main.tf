#1.Configure the provider
terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "duren_terraform"
    key    = "terraform.tfstate"
    region = "ap-southeast-3" 
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-southeast-3"
}

#2.Create VPC
resource "aws_vpc" "vpc1" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"       //the instance is running on shared tenancy, different customers share the same physical hardware. 

  tags = {
    Name = "duren_vpc"
    Managed_by = "terraform"
  }
}

#3.Create internet gateway
resource "aws_internet_gateway" "igw1" {
  vpc_id = aws_vpc.vpc1.id

  tags = {
    Name = "duren_vpc"
    Managed_by = "terraform"
  }
}

#4.Create public subnet 1
resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "duren_pub_sub_1"
    Managed_by = "terraform"
  }
}

#5.Create private subnet 1
resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.vpc1.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "duren_pri_sub_1"
    Managed_by = "terraform"
  }
}

#6.Create Public route table 
resource "aws_route_table" "public_RT" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw1.id          //public_subnet using IGW
  }

  tags = {
    Name = "duren_pub_rt"
    Managed_by = "terraform"
  }
}

# Create public subnet association
resource "aws_route_table_association" "pubsub1_pubrt" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_RT.id
}

#7.Create an Elastic IP
resource "aws_eip" "nat_eip" {
  vpc = true
}

# Create Nat_Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = aws_subnet.private_subnet_1.id
}

# Create Private route table
resource "aws_route_table" "private_RT" {
  vpc_id = aws_vpc.vpc1.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "duren_pri_rt"
    Managed_by = "terraform"
  }
}

# Create private subnet association
resource "aws_route_table_association" "prisub1_prirt" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_RT.id
}

# Create Security Group for EC2 Instances
resource "aws_security_group" "instance_sg" {
  name        = "duren-ec2-sg"
  description = "Allow Port SSH and HTTP traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]         # Allow SSH from anywhere
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]    # Allow HTTP from anywhere
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]    #Allow all outbound traffic
  }

  tags = {
    Name = "duren-ec2-sg"
  }
}


#8.Create a Launch Template for the EC2 Instances
resource "aws_launch_template" "duren_t2_med_tmp" {
  name_prefix = "duren_t2_medium_template"
  image_id = "ami-duren001"         #just sample, so replace with your AMI ID
  instance_type = "t2.medium"
  key_name = "my-key-pair"          #Replace with your key to SSH

  network_interface {
    device_index = 0
    subnet_id     = aws_subnet.private_subnet_1.id            # Reference your private subnet
    security_groups = [aws_security_group.instance_sg.id]     # Reference your security group
  }
}

#9. Create the Auto Scaling Group
resource "aws_autoscaling_group" "duren_asg" {
  name                = "duren_asg"
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id]        # Replace with your private subnet IDs

  min_size             = 2
  max_size             = 5
  desired_capacity     = 2

  launch_template {
    id = aws_launch_template.duren_t2_med_tmp.id
  }

  tags = {
    Name = "Terraform-duren-private-asg"
  }
}

# Create Scaling Policy
resource "aws_autoscaling_policy" "duren_cpu_scaling" {
  adjustment_type = "PercentChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.duren_asg.name
  scaling_adjustment      = 1                   # Increase by 1 instance
  cooldown                = "60"

  step_adjustments {
    metric_interval = "60"
    metric_name     = "CPUUtilization"
    namespace       = "AWS/EC2"
    statistic       = "Average"
    comparison_operator = "GreaterThanThreshold"
    threshold       = "45"
    adjustment_type = "PercentChangeInCapacity"
    scaling_adjustment      = 1
  }
}

#10. CloudWatch Metrics for Monitoring
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "CPUUtilizationAlarm"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "80"                    # Adjust threshold as needed
  comparison_operator = "GreaterThanThreshold"
  alarm_description   = "Alarm if CPU utilization exceeds 80%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.duren_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "memory_alarm" {
  alarm_name          = "MemoryUtilizationAlarm"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "80" # Adjust threshold as needed
  comparison_operator = "GreaterThanThreshold"
  alarm_description   = "Alarm if Memory utilization exceeds 80%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.duren_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check_failure_alarm" {
  alarm_name          = "EC2InstanceStatusCheckFailureAlarm"
  alarm_description   = "Alarm if EC2 instance status checks fail"
  metric_name         = "StatusCheckFailure"
  namespace           = "AWS/EC2"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  //alarm_actions        = [aws_sns_topic.notification_topic.arn]       #opsional
  //ok_actions          = [aws_sns_topic.notification_topic.arn]        #opsional
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.duren_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "network_in_alarm" {
  alarm_name          = "NetworkInAlarm"
  metric_name         = "NetworkIn"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "100"                       # Adjust threshold as needed
  comparison_operator = "GreaterThanThreshold"
  alarm_description   = "Alarm if Network In exceeds 100 Mbps"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.duren_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "network_out_alarm" {
  alarm_name          = "NetworkOutAlarm"
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = "60"
  evaluation_periods  = "1"
  threshold           = "100"                   # Adjust threshold as needed
  comparison_operator = "GreaterThanThreshold"
  alarm_description   = "Alarm if Network Out exceeds 100 Mbps"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.duren_asg.name
  }
}