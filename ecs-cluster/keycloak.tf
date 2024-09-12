data "aws_caller_identity" "current" {}

data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  owners = ["amazon"]
}

locals {
  container-port    = 8443
  management-port   = 9000
  keycloak-hostname = var.keycloak-hostname == "" ? aws_lb.keycloak.dns_name : var.keycloak-hostname

  vpc_id             = var.vpc-id == "" ? module.vpc[0].vpc_id : var.vpc-id
  public_subnets     = length(var.public-subnets) == 0 ? module.vpc[0].public_subnets : var.public-subnets
  private_subnets    = length(var.private-subnets) == 0 ? module.vpc[0].private_subnets : var.private-subnets
  db_private_subnets = length(var.db-private-subnets) == 0 ? module.vpc[0].private_subnets : var.db-private-subnets
}

resource "random_string" "initial-keycloak-password" {
  length = 20
}

resource "random_string" "secretmanager_name" {
  length  = 3
  upper   = false
  special = false
  numeric = false
}

resource "random_password" "db-password" {
  length  = 20
  special = false
}

# Networking

resource "aws_security_group" "rds" {
  name   = "${var.name}-sg-rds"
  vpc_id = local.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs-task-keycloak.id]
  }
}

resource "aws_security_group" "alb" {
  name   = "${var.name}-sg-alb"
  vpc_id = local.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = var.lb-cidr-blocks-in
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = var.lb-cidr-blocks-in
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs-task-keycloak" {
  name   = "${var.name}-sg-task-keycloak"
  vpc_id = local.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = local.container-port
    to_port         = local.container-port
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    protocol        = "tcp"
    from_port       = local.management-port
    to_port         = local.management-port
    security_groups = [aws_security_group.alb.id]
  }
  ingress {
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Load balancer

resource "aws_lb" "keycloak" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnets

  enable_deletion_protection = false

  preserve_host_header = true
}

resource "aws_alb_target_group" "keycloak" {
  name        = "${var.name}-tg"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTPS"
    matcher             = "200"
    timeout             = "5"
    path                = "/health"
    port                = local.management-port
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_lb.keycloak.id
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      host        = local.keycloak-hostname
      port        = 443
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_alb_listener" "https" {
  load_balancer_arn = aws_lb.keycloak.id
  port              = 443
  protocol          = "HTTPS"

  # https://docs.aws.amazon.com/elasticloadbalancing/latest/application/create-https-listener.html
  # ssl_policy        = "ELBSecurityPolicy-2016-08"
  ssl_policy      = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn = var.loadbalancer-certificate-arn

  default_action {
    target_group_arn = aws_alb_target_group.keycloak.id
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "https_redirect_canonical" {
  listener_arn = aws_alb_listener.https.arn
  count        = var.keycloak-hostname == "" ? 0 : 1

  action {
    type = "redirect"
    redirect {
      host        = local.keycloak-hostname
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = [aws_lb.keycloak.dns_name]
    }
  }
}

# MySQL

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.name}-db-password-${random_string.secretmanager_name.result}"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db-password.result
}

resource "aws_db_parameter_group" "keycloak" {
  name   = "${var.name}-keycloak"
  family = "mysql8.0"

  parameter {
    name         = "character_set_server"
    value        = "utf8mb4"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "explicit_defaults_for_timestamp"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "lower_case_table_names"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "time_zone"
    value        = "Asia/Seoul"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_subnet_group" "keycloak" {
  name       = "${var.name}-keycloak"
  subnet_ids = local.db_private_subnets
}

resource "aws_db_instance" "keycloak" {
  identifier = "${var.name}-keycloak-db"
  # identifier            = "${var.name}-db"
  instance_class        = var.db-instance-type
  allocated_storage     = 5
  max_allocated_storage = 20
  engine                = "mysql"
  engine_version        = "8.0"
  storage_encrypted     = false

  # By default changes are queued up for the maintenance window
  # If keycloak desired-count=0 then we can apply straight away
  apply_immediately = (var.desired-count < 1)

  # Max 35 days https://aws.amazon.com/rds/features/backup/
  backup_retention_period  = 1
  delete_automated_backups = true
  deletion_protection      = false

  db_name                      = var.db-name
  username                     = var.db-username
  password                     = aws_secretsmanager_secret_version.db_password.secret_string
  db_subnet_group_name         = aws_db_subnet_group.keycloak.name
  vpc_security_group_ids       = [aws_security_group.rds.id]
  parameter_group_name         = aws_db_parameter_group.keycloak.name
  publicly_accessible          = false
  skip_final_snapshot          = true
  performance_insights_enabled = false

  snapshot_identifier = var.db-snapshot-identifier
}

# task execution role

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.name}-ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  ]
}

# task task role

# resource "aws_iam_role" "ecs_task_role" {
#   name = "${var.name}-ecsTaskRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole",
#         Principal = {
#           Service = "ecs-tasks.amazonaws.com"
#         }
#         Effect = "Allow"
#       }
#     ]
#   })

#   managed_policy_arns = [
#     "arn:aws:iam::aws:policy/AdministratorAccess"
#   ]
# }

# Keycloak

## Launch template for all EC2 instances that are part of the ECS cluster

resource "aws_launch_template" "ecs_launch_template" {
  name                   = "${var.name}-EC2-LaunchTemplate"
  image_id               = data.aws_ami.amazon_linux_2.id
  instance_type          = var.instance-type
  key_name               = var.key_name
  user_data              = base64encode(data.template_file.user_data.rendered)
  vpc_security_group_ids = [aws_security_group.ecs-task-keycloak.id]

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_instance_role_profile.arn
  }

  monitoring {
    enabled = true
  }
}

data "template_file" "user_data" {
  template = file("user_data.sh")

  vars = {
    ecs_cluster_name = aws_ecs_cluster.ecs.name
  }
}

# ec2 instance profile
resource "aws_iam_role" "ec2_instance_role" {
  name               = "${var.name}_EC2_InstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_instance_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ec2_instance_role_policy" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ec2_instance_role_profile" {
  name = "${var.name}_EC2_InstanceRoleProfile"
  role = aws_iam_role.ec2_instance_role.id
}

data "aws_iam_policy_document" "ec2_instance_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "ec2.amazonaws.com",
        "ecs.amazonaws.com"
      ]
    }
  }
}

# ecs task

resource "aws_ecs_task_definition" "keycloak" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]
  # 1024 cpu units = 1 vCPU
  cpu                = 1024
  memory             = 2048
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  # task_role_arn      = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([{
    name  = "${var.name}-container"
    image = var.keycloak-image
    # command   = ["start", "--optimized"]
    essential = true
    environment = [
      # https://www.keycloak.org/server/all-config
      {
        name  = "KC_DB_URL"
        value = "jdbc:mysql://${aws_db_instance.keycloak.endpoint}/${aws_db_instance.keycloak.db_name}"
      },
      {
        name  = "KC_DB_USERNAME"
        value = var.db-username
      },
      {
        name  = "KC_DB_PASSWORD"
        value = aws_secretsmanager_secret_version.db_password.secret_string
      },
      {
        name  = "KEYCLOAK_ADMIN"
        value = "admin"
      },
      # Only used for initial setup
      {
        name  = "KEYCLOAK_ADMIN_PASSWORD"
        value = random_string.initial-keycloak-password.result
      },
      {
        name  = "KC_HOSTNAME"
        value = local.keycloak-hostname
      },
      # https://www.keycloak.org/server/reverseproxy
      # AWS load balancers set X-Forwarded not Forwarded
      # https://docs.aws.amazon.com/elasticloadbalancing/latest/application/x-forwarded-headers.html
      {
        name  = "KC_PROXY_HEADERS"
        value = "xforwarded"
      },
      {
        name  = "KC_LOG_LEVEL"
        value = var.keycloak-loglevel
      },
    ]
    portMappings = [
      {
        protocol      = "tcp"
        containerPort = local.container-port
        hostPort      = local.container-port
        name          = "keycloak-port"
      },
      {
        protocol      = "tcp"
        containerPort = local.management-port
        hostPort      = local.management-port
        name          = "keycloak-management-port"
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-region        = var.region
        awslogs-group         = aws_cloudwatch_log_group.ecs-logs.name
        awslogs-stream-prefix = "keycloak"
      }
    }
  }])
}

resource "aws_ecs_service" "keycloak" {
  name                               = "${var.name}-service"
  cluster                            = aws_ecs_cluster.ecs.id
  task_definition                    = aws_ecs_task_definition.keycloak.arn
  desired_count                      = var.desired-count
  deployment_minimum_healthy_percent = (var.desired-count < 1) ? 0 : 100
  deployment_maximum_percent         = max(100, var.desired-count * 200)
  launch_type                        = "EC2"

  network_configuration {
    security_groups = [
      aws_security_group.rds.id,
      aws_security_group.ecs-task-keycloak.id
    ]
    subnets = local.private_subnets
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.keycloak.arn
    container_name   = "${var.name}-container"
    container_port   = local.container-port
  }

  # Java applications can be very slow to start
  health_check_grace_period_seconds = 180

  ## Spread tasks evenly accross all Availability Zones for High Availability
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  ## Make use of all available space on the Container Instances
  ordered_placement_strategy {
    type  = "binpack"
    field = "memory"
  }

  ## Do not update desired count again to avoid a reset to this number on every deployment
  lifecycle {
    ignore_changes = [desired_count]
  }

  # ECS Service Connect configuration
  service_connect_configuration {
    enabled   = true
    namespace = var.ecs_namespace

    service {
      port_name      = "keycloak-port"
      discovery_name = "keycloak"
      client_alias {
        port     = local.container-port
        dns_name = "keycloak-service.local"
      }
    }
  }
}

# ECS service role / awsvpc 네트워크 모드 사용시 불필요

# resource "aws_iam_role" "ecs_service_role" {
#   name               = "${var.name}_ECS_ServiceRole"
#   assume_role_policy = data.aws_iam_policy_document.ecs_service_policy.json
# }

# data "aws_iam_policy_document" "ecs_service_policy" {
#   statement {
#     actions = ["sts:AssumeRole"]
#     effect  = "Allow"

#     principals {
#       type        = "Service"
#       identifiers = ["ecs.amazonaws.com", ]
#     }
#   }
# }

# resource "aws_iam_role_policy" "ecs_service_role_policy" {
#   name   = "${var.name}_ECS_ServiceRolePolicy"
#   policy = data.aws_iam_policy_document.ecs_service_role_policy.json
#   role   = aws_iam_role.ecs_service_role.id
# }

# data "aws_iam_policy_document" "ecs_service_role_policy" {
#   statement {
#     effect = "Allow"
#     actions = [
#       "ec2:AuthorizeSecurityGroupIngress",
#       "ec2:Describe*",
#       "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
#       "elasticloadbalancing:DeregisterTargets",
#       "elasticloadbalancing:Describe*",
#       "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
#       "elasticloadbalancing:RegisterTargets",
#       "ec2:DescribeTags",
#       "logs:CreateLogGroup",
#       "logs:CreateLogStream",
#       "logs:DescribeLogStreams",
#       "logs:PutSubscriptionFilter",
#       "logs:PutLogEvents"
#     ]
#     resources = ["*"]
#   }
# }
