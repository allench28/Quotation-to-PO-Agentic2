import boto3
import json

def create_s3_buckets():
    s3 = boto3.client('s3')
    
    # Create document storage bucket
    doc_bucket = f"quotation-docs-{boto3.Session().region_name}-{hash(boto3.Session().get_credentials().access_key) % 10000}"
    s3.create_bucket(Bucket=doc_bucket)
    
    # Create web hosting bucket
    web_bucket = f"quotation-web-{boto3.Session().region_name}-{hash(boto3.Session().get_credentials().access_key) % 10000}"
    s3.create_bucket(Bucket=web_bucket)
    
    # Configure web bucket for static hosting
    s3.put_bucket_website(
        Bucket=web_bucket,
        WebsiteConfiguration={
            'IndexDocument': {'Suffix': 'index.html'},
            'ErrorDocument': {'Key': 'error.html'}
        }
    )
    
    return doc_bucket, web_bucket

if __name__ == "__main__":
    doc_bucket, web_bucket = create_s3_buckets()
    print(f"S3 buckets created: {doc_bucket}, {web_bucket}")