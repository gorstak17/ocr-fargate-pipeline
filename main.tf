data "aws_availability_zones" "available" {}

locals {
  subnets         = [for s in aws_subnet.public : s.id]
  security_groups = [aws_security_group.ecs_sg.id]
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "ocr_bucket" {
  bucket = "ocr-bucket-${random_id.bucket_id.hex}"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_ecs_cluster" "ocr_cluster" {
  name = "ocr-cluster"
}


resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


resource "aws_ecs_task_definition" "ocr_task" {
  family                   = "ocrmypdf-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([{
    name      = "ocrmypdf"
    image     = "jbarlow83/ocrmypdf"
    essential = true
    # run OCR
    command   = ["ocrmypdf", "--version"]
    logConfiguration = {
      logDriver = "awslogs"
      options   = {
        "awslogs-group"         = "/ecs/ocrmypdf"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_sqs_queue" "ocr_queue" {
  name = "ocrmypdf-queue"
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambdaEcsRunTaskRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_logs_policy" {
  name = "lambda-cloudwatch-logs"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_logs_policy.arn
}



resource "aws_iam_policy" "lambda_policy" {
  name   = "lambdaEcsRunTaskPolicy"
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action   = [
          "ecs:RunTask",
          "iam:PassRole"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action   = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ],
        Effect   = "Allow",
        Resource = aws_sqs_queue.ocr_queue.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


resource "aws_lambda_function" "trigger_ecs_task" {
  function_name    = "TriggerOCREcsTask"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  filename         = "lambda_function.zip"
  source_code_hash = filebase64sha256("lambda_function.zip")
  environment {
    variables = {
      CLUSTER_NAME    = aws_ecs_cluster.ocr_cluster.name
      TASK_DEFINITION = aws_ecs_task_definition.ocr_task.family
      SUBNETS         = join(",", local.subnets)           # Comma-separated subnet IDs
      SECURITY_GROUPS = join(",", local.security_groups)     # Comma-separated security group IDs
    }
  }
}


resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.ocr_queue.arn
  function_name    = aws_lambda_function.trigger_ecs_task.arn
  batch_size       = 1
  enabled          = true
}



resource "aws_vpc" "ocr_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "ocr-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.ocr_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.ocr_vpc.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  tags = { Name = "ocr-subnet-${count.index}" }
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "Allow ECS Fargate outbound internet"
  vpc_id      = aws_vpc.ocr_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

   tags = {
    Name = "ecs-sg"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.ocr_vpc.id
  tags = {
    Name = "ocr-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ocr_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    Name = "ocr-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_cloudwatch_log_group" "ocr_logs" {
  name              = "/ecs/ocrmypdf"
  retention_in_days = 3

  tags = {
    Name = "OCR Logs"
  }
}