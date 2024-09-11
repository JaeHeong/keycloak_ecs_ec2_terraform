# ecs
resource "aws_cloudwatch_log_group" "ecs-logs" {
  name              = var.name
  retention_in_days = 7
}

resource "aws_ecs_cluster" "ecs" {
  name = var.name

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs-logs.name
      }
    }
  }
}
