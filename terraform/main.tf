terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "main_bucket" {
  bucket = var.bucket_name
  acl    = "public-read"

  website {
    index_document = "index.html"
  }

  cors_rule {
    allowed_methods = [
    "GET"]
    allowed_origins = [
    "*"]
  }

  versioning {
    enabled = true
  }

  logging {
    target_bucket = aws_s3_bucket.log_bucket.id
    target_prefix = "log/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.bucket_name}-log"
  acl    = "log-delivery-write"

  versioning {
    enabled = true
  }

  logging {
    target_bucket = "${var.bucket_name}-log"
    target_prefix = "log/"
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_object" "frontend" {
  bucket       = aws_s3_bucket.main_bucket.id
  key          = "index.html"
  source       = "${path.root}/../frontend/index.local.html"
  acl          = "public-read"
  content_type = "text/html"

  depends_on = [null_resource.replace-host]
}

data "archive_file" "backend_zip" {
  type        = "zip"
  source_file = "${path.root}/../backend/index.js"
  output_path = "${path.root}/../backend/backend.zip"
}

resource "aws_s3_bucket_object" "backend" {
  bucket       = aws_s3_bucket.main_bucket.id
  key          = "backend.zip"
  source       = "${path.root}/../backend/backend.zip"
  content_type = "application/zip"
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_api_gateway_rest_api" "hello-gateway" {
  name        = "hello-gateway"
  description = "Gateway for hello Lambda function"
}

resource "aws_api_gateway_resource" "hello" {
  rest_api_id = aws_api_gateway_rest_api.hello-gateway.id
  parent_id   = aws_api_gateway_rest_api.hello-gateway.root_resource_id
  path_part   = "hello"
}

resource "aws_api_gateway_method" "get_hello" {
  authorization = "NONE"
  http_method   = "GET"
  resource_id   = aws_api_gateway_resource.hello.id
  rest_api_id   = aws_api_gateway_rest_api.hello-gateway.id

  request_parameters = {
    "method.request.querystring.input" = true
  }
}

resource "aws_api_gateway_integration" "hello_integration" {
  http_method             = "GET"
  resource_id             = aws_api_gateway_resource.hello.id
  rest_api_id             = aws_api_gateway_rest_api.hello-gateway.id
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.hello_lambda.invoke_arn
}

resource "aws_api_gateway_method_response" "response_200" {
  rest_api_id = aws_api_gateway_rest_api.hello-gateway.id
  http_method = aws_api_gateway_method.get_hello.http_method
  resource_id = aws_api_gateway_resource.hello.id
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  depends_on = [aws_api_gateway_rest_api.hello-gateway]
}

resource "aws_api_gateway_integration_response" "integration_response" {
  http_method = aws_api_gateway_method.get_hello.http_method
  resource_id = aws_api_gateway_resource.hello.id
  rest_api_id = aws_api_gateway_rest_api.hello-gateway.id
  status_code = aws_api_gateway_method_response.response_200.status_code

  response_templates = {
    "application/json" = ""
  }
  depends_on = [aws_api_gateway_integration.hello_integration]
}

resource "aws_lambda_permission" "gateway_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  statement_id  = "AllowExecutionFromAPIGateway"

  source_arn = "${aws_api_gateway_rest_api.hello-gateway.execution_arn}/*/*/hello"
}

resource "aws_api_gateway_deployment" "default_deployment" {
  rest_api_id = aws_api_gateway_rest_api.hello-gateway.id
  stage_name  = "default"
  depends_on  = [aws_api_gateway_integration.hello_integration]
}

resource "aws_lambda_function" "hello_lambda" {
  s3_bucket     = aws_s3_bucket.main_bucket.id
  s3_key        = aws_s3_bucket_object.backend.id
  function_name = "hello"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"
  publish       = true

  tracing_config {
    mode = "PassThrough"
  }

  source_code_hash = filebase64sha256(data.archive_file.backend_zip.output_path)

  runtime = "nodejs12.x"
}

// Hack to ensure index.html is pointed at gateway - template file syntax in TF conflicts with JS
resource "null_resource" "replace-host" {
  provisioner "local-exec" {
    command = "sed 's#REPLACE_URL#${aws_api_gateway_deployment.default_deployment.invoke_url}/hello#' ../frontend/index.html > ../frontend/index.local.html"
  }
}

output "url" {
  value = "http://${aws_s3_bucket.main_bucket.website_endpoint}"
}