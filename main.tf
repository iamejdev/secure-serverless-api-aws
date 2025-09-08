# --- IAM Role for Lambda ---

resource "aws_iam_role" "lambda_exec_role" {
  name = "secure-api-lambda-exec-role"

  # This is the trust policy. It specifies that the AWS Lambda service
  # is the principal trusted to assume this role.
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "Lambda-Execution-Role"
  }
}

# Attaches the AWS-managed policy for basic Lambda execution permissions (CloudWatch Logs).
resource "aws_iam_role_policy_attachment" "lambda_logs_policy" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Lambda Function & API Gateway ---

# Package the Python source code into a zip archive.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/lambda_deployment_package.zip"
}

# Create the Lambda function resource.
resource "aws_lambda_function" "secure_api_lambda" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "SecureAPILambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "lambda_function.handler" # Filename.FunctionName
  runtime       = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = {
    Name = "Secure-API-Lambda"
  }
}

# Create the API Gateway REST API.
resource "aws_api_gateway_rest_api" "api" {
  name        = "SecureAPIGateway"
  description = "API Gateway for the secure serverless API project"
}

# Create a resource within the API (e.g., a path like "/hello").
resource "aws_api_gateway_resource" "hello_resource" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "hello"
}

# Create a GET method for the "/hello" resource.
resource "aws_api_gateway_method" "get_method" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hello_resource.id
  http_method   = "GET"
  authorization = "NONE" # This makes the endpoint public.
}

# Create the integration to link the GET method to the Lambda function.
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hello_resource.id
  http_method             = aws_api_gateway_method.get_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.secure_api_lambda.invoke_arn
}

# Deploy the API to make it accessible.
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # This empty triggers block is a trick to tell Terraform to redeploy
  # the API whenever any of the other API resources change.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.hello_resource.id,
      aws_api_gateway_method.get_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Create a "prod" stage for the deployment.
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}

# Grant permission for the API Gateway to invoke the Lambda function.
resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secure_api_lambda.function_name
  principal     = "apigateway.amazonaws.com"

  # This source_arn limits the permission to only our specific API.
  source_arn = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}