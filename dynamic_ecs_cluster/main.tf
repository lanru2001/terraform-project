
#How To Create a Dynamic AWS ECS Cluster With Terraform
resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment}-cluster"
  tags = var.tags
}

resource "aws_ecs_service" "fargate-microservices" {
  for_each      = var.create_microservices == true ? var.fargate_microservices : {}
  name          = each.value["name"]
  cluster       = aws_ecs_cluster.cluster.id
  desired_count = each.value["desired_count"]
  launch_type   = each.value["launch_type"]
  depends_on = [aws_ecs_cluster.cluster,
  aws_ecs_task_definition.ecs_tasks]
  task_definition = each.value["task_definition"]

  network_configuration {
    subnets         = var.ecs_service_subnets
    security_groups = [aws_security_group.ecs_security_groups[each.value["security_group_mapping"]].id]
  }
}

resource "aws_security_group" "ecs_security_groups" {
  vpc_id = var.vpc_id

  for_each = var.security_groups
  name     = "${var.environment}-${each.value["ingress_port"]}"

  ingress {
    from_port   = each.value["ingress_port"]
    to_port     = each.value["ingress_port"]
    protocol    = each.value["ingress_protocol"]
    cidr_blocks = each.value["ingress_cidr_blocks"]
  }

  egress {
    from_port   = each.value["egress_port"]
    to_port     = each.value["egress_port"]
    protocol    = each.value["egress_protocol"]
    cidr_blocks = each.value["egress_cidr_blocks"]
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "ecs_tasks" {
  for_each = var.create_tasks == true ? var.ecs_tasks : {}
  family   = each.value["family"]
  container_definitions = templatefile(each.value["container_definition"], "${merge("${var.extra_template_variables}",
    {
      container_name        = each.value["family"],
      docker_image          = "${var.docker_image}:${var.docker_tag}",
      aws_logs_group        = "/aws/fargate/${aws_ecs_cluster.cluster.name}/${each.value["family"]}/${var.environment}",
      aws_log_stream_prefix = each.value["family"],
      aws_region            = var.region,
      container_port        = each.value["container_port"]
  })}")

  task_role_arn            = aws_iam_role.ecs_task_role.arn
  network_mode             = var.task_definition_network_mode
  cpu                      = each.value["cpu"]
  memory                   = each.value["memory"]
  requires_compatibilities = [var.ecs_launch_type == "FARGATE" ? var.ecs_launch_type : null]
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  tags = merge({
    "Name"        = "${each.value["family"]}-${var.environment}"
    "Description" = "Task definition for ${each.value["family"]}"
    }, var.tags
  )
}


resource "aws_cloudwatch_log_group" "cw" {
  name              = "/aws/fargate/${aws_ecs_cluster.cluster.name}/${var.environment}"
  retention_in_days = var.cw_logs_retention
  tags = merge({
    "name"        = "${aws_ecs_cluster.cluster.name}-${var.environment}"
    "description" = "Task definition for ${aws_ecs_cluster.cluster.name}"
    }, var.tags
  )
}

data "aws_iam_policy_document" "ecs_task_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}


resource "aws_iam_role" "ecs_task_role" {
  name = "${var.environment}-ecs-task-role"

  assume_role_policy   = data.aws_iam_policy_document.ecs_task_policy.json
  permissions_boundary = "arn:aws:iam::<account>:policy/<policy>"
  tags = merge({
    "name" = "${var.environment}"
    }, var.tags
  )
}

resource "aws_iam_role" "ecs_execution_role" {
  name                 = "${var.environment}-exec-task-role"
  assume_role_policy   = data.aws_iam_policy_document.ecs_task_policy.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/ccoe/developer"
  tags = merge({
    "name" = "${var.environment}"
    }, var.tags
  )
}


