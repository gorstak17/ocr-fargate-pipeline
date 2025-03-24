output "s3_bucket_name" {
  value = aws_s3_bucket.ocr_bucket.bucket
}

output "sqs_queue_url" {
  value = aws_sqs_queue.ocr_queue.id
}

output "subnet_ids" {
  value = aws_subnet.public[*].id
}

output "security_group_id" {
  value = aws_security_group.ecs_sg.id
}
