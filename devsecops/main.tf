################################################################################
# DevSecOps container pipeline (Inspector + CodePipeline)
#
# Terraform replacement for the former static/inspector-codepipeline.yaml
# CloudFormation template. Creates a CodeCommit -> CodeBuild -> Inspector
# approval -> CodeBuild deploy pipeline that scans container images with
# Amazon Inspector and gates deployment on the scan results.
#
# This file is self-contained: the two Lambda handlers are inlined below, so
# you only need this main.tf plus the three pipeline source files (Dockerfile,
# buildspec.yml, deployspec.yml) in the working directory. They are seeded
# into the CodeCommit repo on first apply.
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "aws" {}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

################################################################################
# Variables
################################################################################

variable "kubectl_role_name" {
  type        = string
  description = "IAM role used by kubectl to interact with EKS cluster"
  default     = "EksWorkshopCodeBuildKubectlRole"
}

variable "eks_cluster_name" {
  type        = string
  description = "The name of the EKS cluster created"
  default     = "eks-auto"
}

variable "vpc_id" {
  type        = string
  description = "VPC in which CodeBuild runs so it can reach the EKS cluster API."
}

variable "private_subnet_id" {
  type        = string
  description = "A private subnet (with a NAT route) in the EKS cluster VPC for the CodeBuild project ENIs."
}

variable "codebuild_security_group_id" {
  type        = string
  description = "Security group for the CodeBuild ENIs (the EKS cluster security group works)."
}

variable "code_dir" {
  type        = string
  description = "Directory containing the pipeline source files (Dockerfile, buildspec.yml, deployspec.yml) to seed into CodeCommit."
  default     = "."
}

locals {
  # The pipeline source files seeded into CodeCommit. Listed explicitly so
  # nothing else in the directory (main.tf, terraform state) is committed.
  code_files = ["Dockerfile", "buildspec.yml", "deployspec.yml"]
}

################################################################################
# S3 Bucket (CodePipeline artifacts)
################################################################################

resource "aws_s3_bucket" "codepipeline_artifact_store_bucket" {}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact_store_encryption" {
  bucket = aws_s3_bucket.codepipeline_artifact_store_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "artifact_store_policy" {
  bucket = aws_s3_bucket.codepipeline_artifact_store_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnEncryptedObjectUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.codepipeline_artifact_store_bucket.arn}/*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      },
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "${aws_s3_bucket.codepipeline_artifact_store_bucket.arn}/*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

################################################################################
# ECR
################################################################################

resource "aws_ecr_repository" "container_repository" {
  name = "inspector-workshop"
}

################################################################################
# CodeCommit + source seeding
################################################################################

resource "aws_codecommit_repository" "container_components_repo" {
  repository_name = "ContainerComponentsRepo"
  default_branch  = "main"
}

# Seed the repository with the pipeline source files (Dockerfile,
# buildspec.yml, deployspec.yml) by committing them with the CodeCommit
# CreateCommit API (aws codecommit create-commit). This uses the ambient AWS
# credentials (the IDE instance role) just like every other aws call in the
# workshop -- no git, no credential helper, and no "git config --global"
# required.
resource "null_resource" "codecommit_init" {
  depends_on = [aws_codecommit_repository.container_components_repo]

  triggers = {
    code_hash = join(",", [for f in local.code_files : filemd5("${var.code_dir}/${f}")])
    repo_name = aws_codecommit_repository.container_components_repo.repository_name
    region    = data.aws_region.current.region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      TEMP_DIR=$(mktemp -d)
      PUT_FILES="$TEMP_DIR/putfiles.json"

      # Build the --put-files payload from the explicit source-file list. For
      # blob members inside a JSON structure the AWS CLI expects base64-encoded
      # content, which is what we produce here.
      python3 - "${abspath(var.code_dir)}" > "$PUT_FILES" <<'PY'
import base64, json, os, sys
src = sys.argv[1]
files = ["Dockerfile", "buildspec.yml", "deployspec.yml"]
items = []
for name in files:
    full = os.path.join(src, name)
    with open(full, "rb") as fh:
        items.append({
            "filePath": name,
            "fileContent": base64.b64encode(fh.read()).decode("ascii"),
        })
print(json.dumps(items))
PY

      aws codecommit create-commit \
        --region "${data.aws_region.current.region}" \
        --repository-name "${aws_codecommit_repository.container_components_repo.repository_name}" \
        --branch-name main \
        --author-name "EKS Security Workshop" \
        --email "workshop@example.com" \
        --commit-message "Initial commit" \
        --put-files "file://$PUT_FILES"

      rm -rf "$TEMP_DIR"
    EOT
  }
}

################################################################################
# DynamoDB
################################################################################

resource "aws_dynamodb_table" "container_image_approvals" {
  name         = "ContainerImageApprovals"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ImageDigest"

  attribute {
    name = "ImageDigest"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }
}

################################################################################
# SNS
################################################################################

resource "aws_sns_topic" "build_approval_topic" {
  name = "ContainerApprovalTopic"
}

resource "aws_sns_topic_subscription" "approval_lambda_subscription" {
  topic_arn = aws_sns_topic.build_approval_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.process_pipeline_approval_msg.arn
}

################################################################################
# IAM Roles & Policies
################################################################################

# EventBridge Role
resource "aws_iam_role" "codecommit_event_role" {
  name = "CodeCommitEventRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "codecommit_event_policy" {
  name = "CodeCommitEventPolicy"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "codepipeline:StartPipelineExecution", Resource = "arn:aws:codepipeline:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${aws_codepipeline.container_pipeline.name}" }]
  })
}

resource "aws_iam_role_policy_attachment" "codecommit_event_attach" {
  role       = aws_iam_role.codecommit_event_role.name
  policy_arn = aws_iam_policy.codecommit_event_policy.arn
}

# CodeBuild Service Role - Build
resource "aws_iam_role" "codebuild_service_role" {
  name = "CodeBuildServiceRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "codebuild_service_policy" {
  name = "CodeBuildServicePolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["codebuild:CreateReportGroup", "codebuild:CreateReport", "codebuild:UpdateReport", "codebuild:BatchPutTestCases", "codebuild:BatchPutCodeCoverages"], Resource = "arn:aws:codebuild:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:report-group/container-build-blog-*" },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:GetAuthorizationToken", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:DescribeImages"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:CreateNetworkInterface", "ec2:DescribeDhcpOptions", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs", "ec2:CreateNetworkInterfacePermission"], Resource = "*" },
      { Effect = "Allow", Action = ["eks:Describe*"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.codepipeline_artifact_store_bucket.arn}/*" },
      { Effect = "Allow", Action = ["sts:AssumeRole"], Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.kubectl_role_name}" },
      { Effect = "Allow", Action = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"], Resource = aws_ecr_repository.container_repository.arn }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_service_attach" {
  role       = aws_iam_role.codebuild_service_role.name
  policy_arn = aws_iam_policy.codebuild_service_policy.arn
}

# CodeBuild Deploy Service Role
resource "aws_iam_role" "codebuild_deploy_service_role" {
  name = "CodeBuildDeployServiceRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "codebuild_deploy_policy" {
  name = "root"
  role = aws_iam_role.codebuild_deploy_service_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sts:AssumeRole"], Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.kubectl_role_name}" },
      { Effect = "Allow", Action = ["eks:Describe*"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ec2:CreateNetworkInterface", "ec2:DescribeDhcpOptions", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs", "ec2:CreateNetworkInterfacePermission"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.codepipeline_artifact_store_bucket.arn}/*" },
      { Effect = "Allow", Action = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability", "ecr:PutImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload"], Resource = aws_ecr_repository.container_repository.arn }
    ]
  })
}

# Pipeline Service Role
resource "aws_iam_role" "pipeline_service_role" {
  name = "PipelineServiceRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "codepipeline.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "pipeline_service_policy" {
  name = "PipelineServicePolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "*", Condition = { StringEqualsIfExists = { "iam:PassedToService" = ["cloudformation.amazonaws.com", "elasticbeanstalk.amazonaws.com", "ec2.amazonaws.com"] } } },
      { Effect = "Allow", Action = ["codecommit:CancelUploadArchive", "codecommit:GetBranch", "codecommit:GetCommit", "codecommit:GetRepository", "codecommit:GetUploadArchiveStatus", "codecommit:UploadArchive"], Resource = "*" },
      { Effect = "Allow", Action = ["elasticbeanstalk:*", "ec2:*", "elasticloadbalancing:*", "autoscaling:*", "cloudwatch:*", "s3:*", "sns:*", "cloudformation:*", "rds:*", "sqs:*"], Resource = "*" },
      { Effect = "Allow", Action = ["lambda:InvokeFunction", "lambda:ListFunctions"], Resource = "*" },
      { Effect = "Allow", Action = ["cloudformation:CreateStack", "cloudformation:DeleteStack", "cloudformation:DescribeStacks", "cloudformation:UpdateStack", "cloudformation:CreateChangeSet", "cloudformation:DeleteChangeSet", "cloudformation:DescribeChangeSet", "cloudformation:ExecuteChangeSet", "cloudformation:SetStackPolicy", "cloudformation:ValidateTemplate"], Resource = "*" },
      { Effect = "Allow", Action = ["codebuild:BatchGetBuilds", "codebuild:StartBuild", "codebuild:BatchGetBuildBatches", "codebuild:StartBuildBatch"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:DescribeImages"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_service_attach" {
  role       = aws_iam_role.pipeline_service_role.name
  policy_arn = aws_iam_policy.pipeline_service_policy.arn
}

# Lambda Role - Process Pipeline Approval Msg
resource "aws_iam_role" "pipeline_approval_msg_role" {
  name = "PipelineApprovalMsgRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "pipeline_approval_msg_policy" {
  name = "PipelineApprovalMsgPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "logs:CreateLogGroup", Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*" },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/process-build-approval-msg:*" },
      { Effect = "Allow", Action = "dynamodb:PutItem", Resource = aws_dynamodb_table.container_image_approvals.arn }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_approval_msg_attach" {
  role       = aws_iam_role.pipeline_approval_msg_role.name
  policy_arn = aws_iam_policy.pipeline_approval_msg_policy.arn
}

# Lambda Role - Eval Container Scan Results
resource "aws_iam_role" "container_scan_results_role" {
  name = "ContainerScanResultsRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_policy" "container_scan_results_policy" {
  name = "ContainerScanResultsPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "logs:CreateLogGroup", Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*" },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/eval-container-scan-results:*" },
      { Effect = "Allow", Action = ["codepipeline:PutApprovalResult", "codepipeline:GetPipelineState"], Resource = "*" },
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:DeleteItem", "dynamodb:PutItem"], Resource = aws_dynamodb_table.container_image_approvals.arn }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "container_scan_results_attach" {
  role       = aws_iam_role.container_scan_results_role.name
  policy_arn = aws_iam_policy.container_scan_results_policy.arn
}

################################################################################
# Lambda Functions (source inlined below so this main.tf is self-contained)
################################################################################

data "archive_file" "process_approval_msg_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda_process_approval_msg.zip"
  source {
    filename = "index.py"
    content  = <<-PY
      # Function that will process the SNS message sent about a pipeline approval
      # request for a container build pipeline.  Information from the message
      # will be stored in a DynamoDB table for further reference

      import json
      import boto3
      import logging
      from datetime import datetime

      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      dynamo_client = boto3.resource('dynamodb')


      def lambda_handler(event, context):
          logger.info('Function Event')
          logger.info(event)

          sns_message = json.loads(event['Records'][0]['Sns']['Message'])

          token = sns_message['approval']['token']
          pipeline = sns_message['approval']['pipelineName']
          stage = sns_message['approval']['stageName']
          approval_action = sns_message['approval']['actionName']
          custom_data = sns_message['approval']['customData']

          image_digest = custom_data.split("=")[1]

          table = dynamo_client.Table('ContainerImageApprovals')
          response = table.put_item(
              Item={
                  'ImageDigest': image_digest,
                  'ApprovalToken': token,
                  'PipelineName': pipeline,
                  'Stage': stage,
                  'ActionName': approval_action,
                  'InsertDate': datetime.utcnow().isoformat()
              }
          )

          logger.info('Table put_item response')
          logger.info(response)

          return {
              'statusCode': 200
          }
    PY
  }
}

data "archive_file" "eval_scan_results_zip" {
  type        = "zip"
  output_path = "${path.module}/.build/lambda_eval_scan_results.zip"
  source {
    filename = "index.py"
    content  = <<-PY
      '''Function that will take in final scan results from the Inspector2 Scan event bridge message
      and evaluate the results to determine if the image can be deployed'''

      import os
      import logging
      from datetime import datetime
      import boto3

      logger = logging.getLogger()
      logger.setLevel(logging.INFO)

      pipeline_client = boto3.client('codepipeline')
      dynamo_client = boto3.resource('dynamodb')


      def update_staging_entry(search_digest, status):
          '''Takes in a container image digest and approval status and puts into DynamoDB'''

          logger.info('Updating Image Approval Stage entry')

          table = dynamo_client.Table('ContainerImageApprovals')
          table.put_item(
              Item={
                  'ImageDigest': search_digest + '##' + status,
                  'InsertDate': datetime.utcnow().isoformat()
              }
          )


      def retrieve_image_approval_details(search_digest):
          '''Takes in a container image digest and looks it up in a DynamoDB table'''

          logger.info('Retrieving image approval stage details.')

          table = dynamo_client.Table('ContainerImageApprovals')
          response = table.get_item(
              Key={
                  'ImageDigest': search_digest
              }
          )

          logger.info(response)

          action_name = response['Item']['ActionName']
          stage = response['Item']['Stage']
          approval_token = response['Item']['ApprovalToken']
          pipeline_name = response['Item']['PipelineName']

          return action_name, stage, approval_token, pipeline_name


      def update_pipeline_approval(pipeline_info, approval_msg, status):
          '''sends approval results to appropriate pipeline stage'''

          logger.info('Starting pipeline approval')

          pipeline_client.put_approval_result(
              pipelineName=pipeline_info[3],
              stageName=pipeline_info[1],
              actionName=pipeline_info[0],
              result={
                  'summary': approval_msg,
                  'status': status
              },
              token=pipeline_info[2]
          )

          logger.info('Pipeline Approval Complete')


      def log_final_results(approval, image_digest, repository_arn, image_tags, reason, sev_list):
          '''Writes the final results of the image vulnerability assessment'''

          logger.info('***********************************')
          logger.info('Final container vulnerability assessment details')
          logger.info('------------------------')
          logger.info('Approval Status: %s', approval)
          logger.info('Approval Reason: %s', reason)
          logger.info('ImageDigest: %s', image_digest)
          logger.info('ImageARN: %s', repository_arn)
          logger.info('Image Tags: %s', image_tags)
          logger.info('Critical Vulnerabilities: %s', sev_list.get('CRITICAL', 0))
          logger.info('High Vulnerabilities: %s', sev_list.get('HIGH', 0))
          logger.info('Medium Vulnerabilities: %s', sev_list.get('MEDIUM', 0))
          logger.info('***********************************')


      def lambda_handler(event, context):
          '''Main lambda handler'''

          logger.info('Event Data')
          logger.info(event)

          scan_status = event["detail"]["scan-status"]
          logger.info('Event scan status: %s', scan_status)

          if scan_status != 'INITIAL_SCAN_COMPLETE':
              logger.info('Scan status is not successful.  Not processing further.')
              return 'Scan status is not successful.  Not processing further.'

          repository_arn = event["detail"]["repository-name"]
          logger.info('Repository ARN: %s', repository_arn)
          resource_type = repository_arn.split(":")[2]
          logger.info('Resource type: %s', resource_type)

          if resource_type != 'ecr':
              logger.info('Resource Type: %s', resource_type)
              logger.info('Resource type is not ECR.  Exiting.')
              return 'Resource type is not ECR.  Exiting.'

          image_digest = event["detail"]["image-digest"]
          image_tags = event["detail"]["image-tags"]
          logger.info('Image digest: %s', image_digest)
          logger.info('Image tags: %s', image_tags)

          critical_max = int(os.environ['Critical_Finding_Threshold'])
          high_max = int(os.environ['High_Finding_Threshold'])
          medium_max = int(os.environ['Medium_Finding_Threshold'])
          threshold_breach = False

          if event["detail"]["finding-severity-counts"]["CRITICAL"] != 0 \
                  and event["detail"]["finding-severity-counts"]["CRITICAL"] >= critical_max:

              threshold_breach = True
              logger.info("*******************************")
              logger.info("We have a CRITICAL vulnerability")
              logger.info("*******************************")

              deploy_approved = 'Rejected'
              reason = f'Critical vulnerability threshold of {critical_max} exceeded'

              log_final_results(deploy_approved, image_digest, repository_arn, image_tags,
                                reason, event["detail"]["finding-severity-counts"])

              pipeline_info = retrieve_image_approval_details(image_digest)
              update_pipeline_approval(pipeline_info, reason, deploy_approved)
              update_staging_entry(image_digest, deploy_approved)

              return reason

          if event["detail"]["finding-severity-counts"]["HIGH"] != 0 \
                  and event["detail"]["finding-severity-counts"]["HIGH"] >= high_max:

              threshold_breach = True
              logger.info("*******************************")
              logger.info("We have a HIGH vulnerability")
              logger.info("*******************************")

              deploy_approved = 'Rejected'
              reason = f'High vulnerability threshold of {high_max} exceeded'

              log_final_results(deploy_approved, image_digest, repository_arn, image_tags,
                                reason, event["detail"]["finding-severity-counts"])

              pipeline_info = retrieve_image_approval_details(image_digest)
              update_pipeline_approval(pipeline_info, reason, deploy_approved)
              update_staging_entry(image_digest, deploy_approved)

              return reason

          if event["detail"]["finding-severity-counts"]["MEDIUM"] != 0 \
                  and event["detail"]["finding-severity-counts"]["MEDIUM"] >= medium_max:

              threshold_breach = True
              logger.info("*******************************")
              logger.info("We have a MEDUIM vulnerability")
              logger.info("*******************************")

              deploy_approved = 'Rejected'
              reason = f'Medium vulnerability threshold of {medium_max} exceeded'

              log_final_results(deploy_approved, image_digest, repository_arn, image_tags,
                                reason, event["detail"]["finding-severity-counts"])

              pipeline_info = retrieve_image_approval_details(image_digest)
              update_pipeline_approval(pipeline_info, reason, deploy_approved)
              update_staging_entry(image_digest, deploy_approved)

              return reason

          if threshold_breach is False:
              deploy_approved = 'Approved'
              reason = 'All vulnerabilities below thresholds'

              log_final_results(deploy_approved, image_digest, repository_arn, image_tags,
                                reason, event["detail"]["finding-severity-counts"])

              pipeline_info = retrieve_image_approval_details(image_digest)
              update_pipeline_approval(pipeline_info, reason, deploy_approved)
              update_staging_entry(image_digest, deploy_approved)

          return {
              'statusCode': 200,
          }
    PY
  }
}

resource "aws_lambda_function" "process_pipeline_approval_msg" {
  function_name    = "process-build-approval-msg"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.pipeline_approval_msg_role.arn
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.process_approval_msg_zip.output_path
  source_code_hash = data.archive_file.process_approval_msg_zip.output_base64sha256
}

resource "aws_lambda_function" "eval_container_scan_results" {
  function_name    = "eval-container-scan-results"
  handler          = "index.lambda_handler"
  role             = aws_iam_role.container_scan_results_role.arn
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.eval_scan_results_zip.output_path
  source_code_hash = data.archive_file.eval_scan_results_zip.output_base64sha256

  environment {
    variables = {
      Critical_Finding_Threshold = "0"
      High_Finding_Threshold     = "0"
      Medium_Finding_Threshold   = "10"
      Low_Finding_Threshold      = "15"
    }
  }
}

resource "aws_lambda_permission" "eval_scan_results_perms" {
  statement_id  = "AllowEventBridgeInvoke"
  function_name = aws_lambda_function.eval_container_scan_results.function_name
  action        = "lambda:InvokeFunction"
  source_arn    = aws_cloudwatch_event_rule.inspector_scan_event_rule.arn
  principal     = "events.amazonaws.com"
}

resource "aws_lambda_permission" "process_approval_msg_perms" {
  statement_id  = "AllowSNSInvoke"
  function_name = aws_lambda_function.process_pipeline_approval_msg.function_name
  action        = "lambda:InvokeFunction"
  source_arn    = aws_sns_topic.build_approval_topic.arn
  principal     = "sns.amazonaws.com"
}

################################################################################
# EventBridge Rules
################################################################################

resource "aws_cloudwatch_event_rule" "container_repo_change_rule" {
  name = "ContainerRepoChangeRule"
  event_pattern = jsonencode({
    source        = ["aws.codecommit"]
    "detail-type" = ["CodeCommit Repository State Change"]
    resources     = [aws_codecommit_repository.container_components_repo.arn]
    detail        = { event = ["referenceCreated", "referenceUpdated"], referenceType = ["branch"], referenceName = ["main"] }
  })
}

resource "aws_cloudwatch_event_target" "codepipeline_target" {
  rule      = aws_cloudwatch_event_rule.container_repo_change_rule.name
  arn       = aws_codepipeline.container_pipeline.arn
  role_arn  = aws_iam_role.codecommit_event_role.arn
  target_id = "codepipeline-ContainerPipeline"
}

resource "aws_cloudwatch_event_rule" "inspector_scan_event_rule" {
  name        = "InspectorContainerScanStatus"
  description = "Event looking for messages from Inspector related to container scan status"
  event_pattern = jsonencode({
    source        = ["aws.inspector2"]
    "detail-type" = ["Inspector2 Scan"]
  })
}

resource "aws_cloudwatch_event_target" "inspector_scan_lambda_target" {
  rule      = aws_cloudwatch_event_rule.inspector_scan_event_rule.name
  arn       = aws_lambda_function.eval_container_scan_results.arn
  target_id = "InspectorScanLambda"
}

################################################################################
# CodeBuild Projects
################################################################################

resource "aws_codebuild_project" "container_build" {
  name         = "container-build"
  service_role = aws_iam_role.codebuild_service_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.region
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "inspector-workshop"
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }
}

resource "aws_codebuild_project" "container_deploy" {
  name         = "container-deploy"
  service_role = aws_iam_role.codebuild_deploy_service_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "deployspec.yml"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.region
    }
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = "inspector-workshop"
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
    environment_variable {
      name  = "EKSCLUSTER"
      value = var.eks_cluster_name
    }
    environment_variable {
      name  = "EKS_KUBECTL_ROLE_ARN"
      value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.kubectl_role_name}"
    }
  }

  vpc_config {
    vpc_id             = var.vpc_id
    subnets            = [var.private_subnet_id]
    security_group_ids = [var.codebuild_security_group_id]
  }
}

################################################################################
# CodePipeline
################################################################################

resource "aws_codepipeline" "container_pipeline" {
  name     = "ContainerBuildDeployPipeline"
  role_arn = aws_iam_role.pipeline_service_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.codepipeline_artifact_store_bucket.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      run_order        = 1
      configuration = {
        RepositoryName       = aws_codecommit_repository.container_components_repo.repository_name
        BranchName           = "main"
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "ContainerBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      run_order        = 2
      namespace        = "BuildVariables"
      configuration    = { ProjectName = aws_codebuild_project.container_build.name }
    }
  }

  stage {
    name = "ContainerVulnerabilityAssessment"
    action {
      name      = "ContainerImageApproval"
      category  = "Approval"
      owner     = "AWS"
      provider  = "Manual"
      version   = "1"
      run_order = 3
      configuration = {
        NotificationArn = aws_sns_topic.build_approval_topic.arn
        CustomData      = "Image_Digest=#{BuildVariables.IMAGE_DIGEST}"
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name             = "ImageDeployment"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput1"]
      run_order        = 4
      namespace        = "BuildVariables1"
      configuration    = { ProjectName = aws_codebuild_project.container_deploy.name }
    }
  }
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "inspector_scan_cluster" {
  name              = "InspectorScanCluster"
  retention_in_days = 30
}

################################################################################
# Outputs
################################################################################

output "codecommit_repo_name" {
  description = "Name of the CodeCommit repository seeded with the pipeline source"
  value       = aws_codecommit_repository.container_components_repo.repository_name
}

output "codecommit_clone_url_http" {
  description = "HTTPS clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.container_components_repo.clone_url_http
}

output "ecr_repository_url" {
  description = "ECR repository URL for the scanned container image"
  value       = aws_ecr_repository.container_repository.repository_url
}

output "pipeline_name" {
  description = "Name of the CodePipeline"
  value       = aws_codepipeline.container_pipeline.name
}
