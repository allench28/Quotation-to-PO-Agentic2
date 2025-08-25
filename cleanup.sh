#!/bin/bash

echo "Starting cleanup of AI Quotation Processor resources..."

REGION="us-east-1"

# Delete Lambda function
echo "Deleting Lambda function..."
aws lambda delete-function --function-name quotation-processor-function --region $REGION 2>/dev/null

# Delete API Gateway
echo "Deleting API Gateway..."
for api_id in $(aws apigateway get-rest-apis --region $REGION --query 'items[?name==`quotation-api`].id' --output text); do
    aws apigateway delete-rest-api --rest-api-id $api_id --region $REGION
done

# Disable CloudFront distributions
echo "Disabling CloudFront distributions..."
for dist_id in $(aws cloudfront list-distributions --query 'DistributionList.Items[?Comment==`Quotation Processor Distribution`].Id' --output text); do
    echo "Disabling distribution: $dist_id"
    ETAG=$(aws cloudfront get-distribution --id $dist_id --query 'ETag' --output text)
    aws cloudfront get-distribution-config --id $dist_id --query 'DistributionConfig' > /tmp/dist-config.json
    sed -i 's/"Enabled": true/"Enabled": false/' /tmp/dist-config.json
    aws cloudfront update-distribution --id $dist_id --distribution-config file:///tmp/dist-config.json --if-match $ETAG 2>/dev/null
done

# Delete S3 buckets
echo "Deleting S3 buckets..."
for bucket in $(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `quotation-`)].Name' --output text); do
    echo "Emptying bucket: $bucket"
    aws s3 rm s3://$bucket --recursive 2>/dev/null
    aws s3api delete-bucket --bucket $bucket --region $REGION 2>/dev/null
done

# Delete DynamoDB table
echo "Deleting DynamoDB table..."
aws dynamodb delete-table --table-name QuotationData --region $REGION 2>/dev/null

# Delete IAM role and policies
echo "Deleting IAM role..."
aws iam detach-role-policy --role-name quotation-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role-policy --role-name quotation-lambda-role --policy-name quotation-policy 2>/dev/null
aws iam delete-role --role-name quotation-lambda-role 2>/dev/null

echo "Cleanup complete!"