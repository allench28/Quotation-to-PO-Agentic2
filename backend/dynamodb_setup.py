import boto3
import json

def create_quotations_table():
    dynamodb = boto3.resource('dynamodb')
    
    table = dynamodb.create_table(
        TableName='QuotationData',
        KeySchema=[
            {
                'AttributeName': 'quotation_id',
                'KeyType': 'HASH'
            }
        ],
        AttributeDefinitions=[
            {
                'AttributeName': 'quotation_id',
                'AttributeType': 'S'
            }
        ],
        BillingMode='PAY_PER_REQUEST'
    )
    
    table.wait_until_exists()
    return table

if __name__ == "__main__":
    create_quotations_table()
    print("DynamoDB table created successfully")