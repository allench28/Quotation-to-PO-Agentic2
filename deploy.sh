#!/bin/bash

echo "Starting AI Quotation Processor deployment..."

# Set variables
REGION="us-east-1"
STACK_NAME="quotation-processor"
LAMBDA_FUNCTION_NAME="quotation-processor-function"

# Create DynamoDB table
echo "Creating DynamoDB table..."
aws dynamodb create-table \
    --table-name QuotationData \
    --attribute-definitions AttributeName=quotation_id,AttributeType=S \
    --key-schema AttributeName=quotation_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

# Create S3 buckets
echo "Creating S3 buckets..."
DOC_BUCKET="quotation-docs-$(date +%s)"
WEB_BUCKET="quotation-web-$(date +%s)"

aws s3 mb s3://$DOC_BUCKET --region $REGION
aws s3 mb s3://$WEB_BUCKET --region $REGION

# Configure web bucket for static hosting
aws s3 website s3://$WEB_BUCKET --index-document index.html

# Create IAM role for Lambda
echo "Creating IAM role..."
aws iam create-role \
    --role-name quotation-lambda-role \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Attach policies
aws iam attach-role-policy \
    --role-name quotation-lambda-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam put-role-policy \
    --role-name quotation-lambda-role \
    --policy-name quotation-policy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": ["s3:*", "dynamodb:*", "bedrock:*"],
                "Resource": "*"
            }
        ]
    }'

# Wait for IAM role propagation
echo "Waiting for IAM role to propagate..."
sleep 30

# Package and deploy Lambda
echo "Deploying Lambda function..."
cd backend
zip -r function.zip lambda_function.py
aws lambda create-function \
    --function-name $LAMBDA_FUNCTION_NAME \
    --runtime python3.9 \
    --role arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/quotation-lambda-role \
    --handler lambda_function.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 60 \
    --memory-size 512 \
    --region $REGION

cd ..

# Create API Gateway
echo "Creating API Gateway..."
API_ID=$(aws apigateway create-rest-api \
    --name quotation-api \
    --region $REGION \
    --query 'id' --output text)

RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --region $REGION \
    --query 'items[0].id' --output text)

# Create upload resource
UPLOAD_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $RESOURCE_ID \
    --path-part upload \
    --region $REGION \
    --query 'id' --output text)

# Create POST method
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $UPLOAD_RESOURCE_ID \
    --http-method POST \
    --authorization-type NONE \
    --region $REGION

# Add Lambda integration
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $UPLOAD_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$(aws sts get-caller-identity --query Account --output text):function:$LAMBDA_FUNCTION_NAME/invocations \
    --region $REGION

# Add Lambda permission
aws lambda add-permission \
    --function-name $LAMBDA_FUNCTION_NAME \
    --statement-id api-gateway-invoke \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$(aws sts get-caller-identity --query Account --output text):$API_ID/*/*" \
    --region $REGION

# Deploy API
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name prod \
    --region $REGION

# Update frontend with API URL
echo "Updating frontend with API URL..."
sed "s/YOUR_API_GATEWAY_URL/https:\/\/$API_ID.execute-api.$REGION.amazonaws.com\/prod/g" frontend/index.html > frontend/index_updated.html

# Deploy frontend
echo "Deploying frontend..."
aws s3 cp frontend/index_updated.html s3://$WEB_BUCKET/index.html

# Create CloudFront distribution
echo "Creating CloudFront distribution..."
DISTRIBUTION_ID=$(aws cloudfront create-distribution \
    --distribution-config '{
        "CallerReference": "'$(date +%s)'",
        "Origins": {
            "Quantity": 1,
            "Items": [{
                "Id": "S3Origin",
                "DomainName": "'$WEB_BUCKET'.s3.amazonaws.com",
                "S3OriginConfig": {"OriginAccessIdentity": ""}
            }]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "S3Origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "MinTTL": 0,
            "ForwardedValues": {"QueryString": false, "Cookies": {"Forward": "none"}}
        },
        "Comment": "Quotation Processor Distribution",
        "Enabled": true
    }' \
    --query 'Distribution.Id' --output text)

echo "Deployment complete!"
echo "CloudFront URL: https://$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query 'Distribution.DomainName' --output text)"
echo "API Gateway URL: https://$API_ID.execute-api.$REGION.amazonaws.com/prod"
echo "S3 Website URL: http://$WEB_BUCKET.s3-website-$REGION.amazonaws.com"