#!/bin/bash

echo "Fixing Lambda IAM role and completing deployment..."

REGION="us-east-1"
LAMBDA_FUNCTION_NAME="quotation-processor-function"
API_ID="m11do12rth"

# Wait for IAM role to propagate
echo "Waiting for IAM role to propagate..."
sleep 30

# Delete and recreate Lambda function with proper role
echo "Recreating Lambda function..."
aws lambda delete-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION 2>/dev/null

cd backend
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

# Complete API Gateway setup
echo "Completing API Gateway setup..."

# Get resource IDs
RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query 'items[0].id' --output text)
UPLOAD_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --query 'items[?pathPart==`upload`].id' --output text)

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

# Update frontend with correct API URL
sed -i "s/YOUR_API_GATEWAY_URL/https:\/\/$API_ID.execute-api.$REGION.amazonaws.com\/prod/g" frontend/index.html

# Re-upload frontend
aws s3 cp frontend/index.html s3://quotation-web-1756118286/

echo "Fix complete!"
echo "API Gateway URL: https://$API_ID.execute-api.$REGION.amazonaws.com/prod"