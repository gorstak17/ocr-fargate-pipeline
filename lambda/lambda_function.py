import json
import os
import boto3


ecs_client = boto3.client('ecs')

def lambda_handler(event, context):
    
    for record in event.get('Records', []):
        body = record.get('body')
        print("Received SQS message:", body)
        response = ecs_client.run_task(
            cluster=os.environ['CLUSTER_NAME'],
            launchType='FARGATE',
            taskDefinition=os.environ['TASK_DEFINITION'],
            networkConfiguration={
                'awsvpcConfiguration': {
                    'subnets': os.environ['SUBNETS'].split(","),
                    'securityGroups': os.environ['SECURITY_GROUPS'].split(","),
                    'assignPublicIp': 'ENABLED'
                }
            }
        )
        print("ECS run_task response:", response)

    return {
        'statusCode': 200,
        'body': json.dumps('ECS task triggered successfully!')
    }
