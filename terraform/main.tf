terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

variable region {
 default = "us-west-2"
}

provider "aws" {
  region = var.region
}

data aws_caller_identity current {}
 
locals {
 prefix = "prediction"
 account_id          = data.aws_caller_identity.current.account_id
 ecr_repository_name = "${local.prefix}-api-repository"
 ecr_image_tag       = "latest"
}


resource "aws_ecr_repository" "api_ecr" {
  name = local.ecr_repository_name
}

resource null_resource ecr_image {
 triggers = {
   python_file = md5(file(abspath("${path.module}/../app/main.py")))
   docker_file = md5(file(abspath("${path.module}/../Dockerfile")))
 }
 
 provisioner "local-exec" {
   command = <<EOF
           aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${local.account_id}.dkr.ecr.${var.region}.amazonaws.com
           cd ${path.module}/../
           docker build -t prediction-api-repository .
           docker tag prediction-api-repository:latest ${aws_ecr_repository.api_ecr.repository_url}:${local.ecr_image_tag}
           docker push ${aws_ecr_repository.api_ecr.repository_url}:${local.ecr_image_tag}
       EOF
 }
}

data aws_ecr_image ecs_image {
 depends_on = [
   null_resource.ecr_image
 ]
 repository_name = local.ecr_repository_name
 image_tag       = local.ecr_image_tag
}


data "aws_vpc" "default" {
  depends_on = [
   null_resource.ecr_image
  ]

  default = true
}

data "aws_internet_gateway" "default" {
  depends_on = [
   null_resource.ecr_image
  ]

  filter {
    name = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "subnets" {
  depends_on = [
   null_resource.ecr_image
  ]

  source              = "git::https://github.com/cloudposse/terraform-aws-dynamic-subnets.git?ref=tags/0.32.0"
  namespace           = "rdx"
  stage               = "dev"
  name                = "prediction-api"
  vpc_id              = data.aws_vpc.default.id
  igw_id              = data.aws_internet_gateway.default.id
  cidr_block          = "172.31.64.0/24"
  availability_zones  = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

module "security_group" {
  depends_on = [
   null_resource.ecr_image
  ]

  source = "terraform-aws-modules/security-group/aws//modules/http-80"
  name = "prediction-api-sg"
  vpc_id = data.aws_vpc.default.id
  ingress_cidr_blocks = ["0.0.0.0/0"]
}



module "alb" {
   depends_on = [
   null_resource.ecr_image
  ]

  source = "terraform-aws-modules/alb/aws"
  
  version = "~> 5.0"
  name = "prediction-api-alb"
  vpc_id = data.aws_vpc.default.id
  subnets = module.subnets.public_subnet_ids
  security_groups = [module.security_group.security_group_id]
  target_groups = [
    {
      name = "prediction-api-tg"
      backend_port = 80
      backend_protocol = "HTTP"
      target_type = "ip"
      vpc_id = data.aws_vpc.default.id
      health_check = {
        path = "/docs"
        port = "80"
        matcher = "200-399"
      }
    }
  ]
  http_tcp_listeners = [
    {
      port = "80"
      protocol = "HTTP"
      target_group_index = "0"
    }
  ]
}

resource "aws_ecs_cluster" "cluster" {
  depends_on = [
    null_resource.ecr_image,
    data.aws_vpc.default,
    data.aws_internet_gateway.default,
    module.subnets,
    module.security_group,
    module.alb
  ]

  name = "prediction-api-cluster"
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
        "Effect": "Allow",
        "Principal": {
         "Service": "ecs-tasks.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "ecs_permissions" {
  name        = "my_ecs_permissions"
  description = "Permissions to enable CT"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*",
        "ecs:StartTask",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "ecs_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_permissions.arn
}

module "container_definition" {
  depends_on = [
   null_resource.ecr_image,
   data.aws_vpc.default,
   data.aws_internet_gateway.default,
   module.subnets,
   module.security_group,
   module.alb
  ]

  source = "git::https://github.com/cloudposse/terraform-aws-ecs-container-definition.git?ref=tags/0.44.0"

  container_name  = "prediction-api-container"
  container_image = "${aws_ecr_repository.api_ecr.repository_url}:${local.ecr_image_tag}"

  port_mappings   = [
    {
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
    }
  ]
}

module "ecs_alb_service_task" {
  depends_on = [
    null_resource.ecr_image,
    data.aws_vpc.default,
    data.aws_internet_gateway.default,
    module.subnets,
    module.security_group,
    module.alb
  ]

  source = "git::https://github.com/cloudposse/terraform-aws-ecs-alb-service-task.git?ref=tags/0.40.2"
  
  namespace = "rdx"
  stage = "dev"
  name = "prediction-api"
  container_definition_json = module.container_definition.json_map_encoded_list
  ecs_cluster_arn = aws_ecs_cluster.cluster.arn
  launch_type = "FARGATE"
  vpc_id = data.aws_vpc.default.id
  security_group_ids = [module.security_group.security_group_id]
  subnet_ids = module.subnets.public_subnet_ids
  health_check_grace_period_seconds = 60
  ignore_changes_task_definition = false
  assign_public_ip = true  

  ecs_load_balancers = [
    {
      target_group_arn = module.alb.target_group_arns[0]
      elb_name = ""
      container_name = "prediction-api-container" 
      container_port = 80
    }
  ]
}
