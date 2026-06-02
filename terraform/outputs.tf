output "api_endpoint" {
  description = "HTTP API invoke URL — append /inquiries to start calling the API."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.inquiries.name
}

output "lambda_function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.inquiry.function_name
}

output "lambda_execution_role_arn" {
  description = "IAM execution role ARN."
  value       = aws_iam_role.lambda_exec.arn
}

output "ses_sender_identity" {
  description = "Verified SES sender email address."
  value       = aws_ses_email_identity.sender.email
}
