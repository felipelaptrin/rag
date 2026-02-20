import json


def lambda_handler(event, context):
    print(f"{event = }")
    print(f"{context = }")
    data = {"message": "Hello from Lambda!"}

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(data),
    }
