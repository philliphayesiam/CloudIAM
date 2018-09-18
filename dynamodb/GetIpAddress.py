import json
import boto3
from botocore.vendored import requests
from boto3.dynamodb.conditions import Key, Attr

# Variables for Success or failure
SUCCESS = "SUCCESS"
FAILED = "FAILED"

def lambda_handler(event, context):

    if event['RequestType'] != 'Delete':
        # connect to endpoint and select table
        dynamodb = boto3.resource('dynamodb', region_name='us-east-2', endpoint_url="https://dynamodb.us-east-2.amazonaws.com")
        table = dynamodb.Table('css_cidrs')

        # Get the first unused CIDR
        # Query basically looks like
        #       SELECT *
        #       FROM css_cidrs
        #       WHERE environment='sandbox_ips' and id>0 and used=False
        data = table.query(
            Select='ALL_ATTRIBUTES',
            KeyConditionExpression=Key('environment').eq('sandbox_ips') & Key('id').gt(0),
            FilterExpression=Key("used").eq(False),
            ScanIndexForward=True,
            ConsistentRead=True
        )

        # printing out the unused CIDR we got back
        print("Next IP Address CIDR Available")
        print(data['Items'][0])
        print(data['Items'][0]['id'])
        print(data['Items'][0]['environment'])

        # Since we got the CIDR, now update the used field
        # Query basically looks like
        #       UPDATE css_cidrs
        #       SET used=True
        #       WHERE environment=data['Items'][0]['environment'] and id=data['Items'][0]['id']
        dataUpdate = table.update_item(
            Key={
                'id':data['Items'][0]['id'],
                'environment':data['Items'][0]['environment']
            },
            UpdateExpression="set used = :r",
            ExpressionAttributeValues={
                ':r': True
            },
            ReturnValues="UPDATED_NEW"
        )

        #log the returned/updated attribute to CW
        print dataUpdate['Attributes']

        # starting to build the response object to "send" back to CF
        responseData = { 'Ip':data['Items'][0]['ipaddress']}
        response = send(event, context, SUCCESS,responseData, None)

        #Return the response
        return {
            "Response" : response
        }
    else:
        responseData = { 'Action':'Deleted Stack'}
        response = send(event, context, SUCCESS,responseData, None)

        #Return the response
        return {
            "Response" : response
        }

# This function uses the "request" library to perform a Put back to the
# custom resource created in the CloudFormation template
def send(event, context, responseStatus, responseData, physicalResourceId):
    responseUrl = event['ResponseURL']

    print("Event: " + str(event))
    print("ResponseURL: " + responseUrl)

    responseBody = {}
    responseBody['Status'] = responseStatus
    responseBody['Reason'] = "See the details in CloudWatch Log Stream: " + context.log_stream_name
    responseBody['PhysicalResourceId'] = physicalResourceId or context.log_stream_name
    responseBody['StackId'] = event['StackId']
    responseBody['RequestId'] = event['RequestId']
    responseBody['LogicalResourceId'] = event['LogicalResourceId']
    responseBody['Data'] = responseData # here is the data object needed by the CloudFormation template !GetAttr Lambda.arn

    # Puts it into JSON (and validates the JSON)
    json_responseBody = json.dumps(responseBody)

    print("Response body: " + str(json_responseBody))

    headers = {
        'content-type' : '',
        'content-length' : str(len(json_responseBody))
    }

    try:
        response = requests.put(responseUrl,data=json_responseBody,headers=headers)
        print("Status code: " + str(response.reason))
        return SUCCESS
    except Exception as e:
        print("send(..) failed executing requests.put(..): " + str(e))
    return FAILED
