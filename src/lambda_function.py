import json

def handler(event, context):
    """
    This function returns a simple hardcoded JSON response.
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'message': 'Hello from a secure Lambda!'})
    }