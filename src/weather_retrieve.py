import boto3
def lambda_handler(event, context):
    result = "Weather Retrieve"
    return {
        'statusCode' : 200,
        'body': result
    }