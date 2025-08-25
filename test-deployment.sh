#!/bin/bash

echo "Testing multi-account deployment capability..."

# Check AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "Error: AWS credentials not configured"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Deploying to AWS Account: $ACCOUNT_ID"

# Validate required permissions
echo "Validating permissions..."
aws iam list-roles --max-items 1 > /dev/null 2>&1 || { echo "Error: IAM permissions required"; exit 1; }
aws s3 ls > /dev/null 2>&1 || { echo "Error: S3 permissions required"; exit 1; }
aws dynamodb list-tables > /dev/null 2>&1 || { echo "Error: DynamoDB permissions required"; exit 1; }

echo "Permission validation complete"
echo "Ready for deployment - run ./deploy.sh"