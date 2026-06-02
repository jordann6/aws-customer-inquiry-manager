locals {
  project     = "inquiry"
  environment = var.environment
  region      = var.region

  common_tags = {
    project     = local.project
    environment = local.environment
    owner       = "jordann6"
    managed_by  = "terraform"
  }
}

# --- DynamoDB -----------------------------------------------------------------

resource "aws_dynamodb_table" "inquiries" {
  name         = "${local.project}-${local.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "inquiry_id"

  attribute {
    name = "inquiry_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# --- SES Email Identity -------------------------------------------------------

resource "aws_ses_email_identity" "sender" {
  email = var.sender_email
}

# --- IAM Role for Lambda ------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "role-${local.project}-lambda-${local.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "lambda_dynamo" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Scan",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.inquiries.arn,
      "${aws_dynamodb_table.inquiries.arn}/index/*",
    ]
  }
}

data "aws_iam_policy_document" "lambda_ses" {
  statement {
    actions   = ["ses:SendEmail"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.sender_email]
    }
  }
}

resource "aws_iam_policy" "lambda_dynamo" {
  name   = "policy-${local.project}-lambda-dynamo-${local.environment}"
  policy = data.aws_iam_policy_document.lambda_dynamo.json
  tags   = local.common_tags
}

resource "aws_iam_policy" "lambda_ses" {
  name   = "policy-${local.project}-lambda-ses-${local.environment}"
  policy = data.aws_iam_policy_document.lambda_ses.json
  tags   = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_dynamo" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_dynamo.arn
}

resource "aws_iam_role_policy_attachment" "lambda_ses" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_ses.arn
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Function ----------------------------------------------------------

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "inquiry" {
  function_name    = "lambda-${local.project}-api-${local.environment}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.inquiries.name
      SUPPORT_EMAIL = var.support_email
      SENDER_EMAIL  = var.sender_email
    }
  }

  tags = local.common_tags
}

# --- API Gateway v2 (HTTP API) ------------------------------------------------

resource "aws_apigatewayv2_api" "inquiry" {
  name          = "api-${local.project}-${local.environment}"
  protocol_type = "HTTP"
  tags          = local.common_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.inquiry.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.inquiry.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "inquiries_create" {
  api_id    = aws_apigatewayv2_api.inquiry.id
  route_key = "POST /inquiries"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "inquiries_list" {
  api_id    = aws_apigatewayv2_api.inquiry.id
  route_key = "GET /inquiries"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "inquiry_get" {
  api_id    = aws_apigatewayv2_api.inquiry.id
  route_key = "GET /inquiries/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "inquiry_status" {
  api_id    = aws_apigatewayv2_api.inquiry.id
  route_key = "PATCH /inquiries/{id}/status"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.inquiry.id
  name        = "$default"
  auto_deploy = true
  tags        = local.common_tags
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inquiry.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.inquiry.execution_arn}/*/*"
}
