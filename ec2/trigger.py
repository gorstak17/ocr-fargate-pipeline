import boto3
import json
import os

queue_url = os.environ["QUEUE_URL"]
bucket_name = os.environ["BUCKET_NAME"]

sqs_client = boto3.client('sqs')

def trigger_ocr(pdf_bucket, pdf_key):
    message = {
        'bucket': pdf_bucket,
        'key': pdf_key
    }
    response = sqs_client.send_message(
        QueueUrl=queue_url,
        MessageBody=json.dumps(message)
    )
    print("Message sent, response:", response)

if __name__ == "__main__":
    trigger_ocr(bucket_name, 'sample.pdf')
