import json
import boto3
import uuid
from datetime import datetime
import base64

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event, context):
    try:
        if event['httpMethod'] == 'POST' and event['path'] == '/upload':
            return handle_upload(event)
        elif event['httpMethod'] == 'GET' and event['path'].startswith('/status'):
            return handle_status(event)
        elif event['httpMethod'] == 'GET' and event['path'].startswith('/data'):
            return handle_data_retrieval(event)
        else:
            return {
                'statusCode': 404,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Not found'})
            }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }

def handle_upload(event):
    quotation_id = str(uuid.uuid4())
    
    # Decode and store document
    file_content = base64.b64decode(event['body'])
    s3.put_object(
        Bucket='quotation-docs',
        Key=f"{quotation_id}.pdf",
        Body=file_content
    )
    
    # Process with Bedrock
    extracted_data = process_with_bedrock(file_content)
    
    # Store in DynamoDB
    table = dynamodb.Table('QuotationData')
    table.put_item(
        Item={
            'quotation_id': quotation_id,
            'timestamp': datetime.now().isoformat(),
            'status': 'completed',
            'extracted_data': extracted_data
        }
    )
    
    return {
        'statusCode': 200,
        'headers': {'Access-Control-Allow-Origin': '*'},
        'body': json.dumps({
            'quotation_id': quotation_id,
            'status': 'completed',
            'data': extracted_data
        })
    }

def process_with_bedrock(file_content):
    response = bedrock.invoke_model(
        modelId='anthropic.claude-3-sonnet-20240229-v1:0',
        body=json.dumps({
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': 1000,
            'messages': [{
                'role': 'user',
                'content': 'Extract company name, email, quote number, date, line items with quantities and prices, subtotal and total from this quotation document.'
            }]
        })
    )
    
    result = json.loads(response['body'].read())
    return result['content'][0]['text']

def handle_status(event):
    quotation_id = event['pathParameters']['id']
    table = dynamodb.Table('QuotationData')
    
    response = table.get_item(Key={'quotation_id': quotation_id})
    
    if 'Item' in response:
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'status': response['Item']['status']})
        }
    else:
        return {
            'statusCode': 404,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Not found'})
        }

def handle_data_retrieval(event):
    quotation_id = event['pathParameters']['id']
    table = dynamodb.Table('QuotationData')
    
    response = table.get_item(Key={'quotation_id': quotation_id})
    
    if 'Item' in response:
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(response['Item'])
        }
    else:
        return {
            'statusCode': 404,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Not found'})
        }