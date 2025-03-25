## 📥 Clone the Repository
```bash
git clone https://github.com/gorstak17/ocr-fargate-pipeline.git
cd ocr-fargate-pipeline
```

## 📦 Package the Lambda Function
```bash
cd lambda
zip ../lambda_function.zip lambda_function.py
cd ..
```

## ☁️ Deploy Infrastructure
```bash
terraform init
terraform apply
```

> **Note:** Terraform provisions a VPC, subnets, route tables, security groups, an S3 bucket, an SQS queue, an ECS Fargate cluster, and a Lambda function with an SQS trigger.

## 📋 Record Deployment Outputs
After deployment completes, note the following Terraform outputs:

- `sqs_queue_url`
- `bucket_name`

## 🚀 Usage

### 1️⃣ Upload a PDF to S3
```bash
export BUCKET_NAME=<your-s3-bucket-name>
aws s3 cp sample.pdf s3://$BUCKET_NAME/
```
> **Note:** Export your S3 bucket name from Terraform output.

### 2️⃣ Trigger the OCR Pipeline
```bash
export QUEUE_URL=<your-sqs-queue-url>
python3 ec2/trigger.py
```
> **Note:** Export your SQS queue url from Terraform output.

This sends a message to SQS, triggering Lambda which launches an ECS Fargate task running `ocrmypdf`.

## 🔍 Monitoring the Workflow
- **S3 Console:** [Verify PDF upload](https://s3.console.aws.amazon.com/s3/home)
- **SQS Console:** [Confirm message in queue](https://console.aws.amazon.com/sqs/v2/home)
- **Lambda Console:** [Check invocation logs](https://console.aws.amazon.com/lambda/home)
- **ECS Console:** [View Fargate task status](https://console.aws.amazon.com/ecs/home)
- **CloudWatch Logs:** [Inspect `ocrmypdf` output logs](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups)

## 🧹 Cleanup
Destroy all resources:
```bash
terraform destroy
```
If the S3 bucket isn’t empty:
```bash
aws s3 rm s3://$BUCKET_NAME --recursive
```

## 📓 Additional Notes
- Recreate `lambda_function.zip` whenever `lambda_function.py` changes.
