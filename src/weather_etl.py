import boto3
def lambda_handler(event, context):
    result = "Weather ETL"
    return {
        'statusCode' : 200,
        'body': result
    }