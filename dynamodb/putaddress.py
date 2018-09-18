import boto3
#client = boto3.client('dynamodb')
dynamodb = boto3.resource('dynamodb', region_name='us-east-2', endpoint_url="https://dynamodb.us-east-2.amazonaws.com")
table = dynamodb.Table('css_cidrs')

cnt = 1
octet = 0
for i in range(0, 65):
    try:
        table.put_item(Item={
            "environment":"sandbox_ips",
            "ipaddress":"10.0." + str(octet) + ".0/23",
            "id":cnt,
            "used":False
            }
        )
        print "ip_address 10.0." + str(octet) + ".0/23 Added to 'sandbox_ips"
        octet+=2
        cnt+=1
    except Exception, e:
        print (e)
