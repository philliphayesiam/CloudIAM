#!/usr/bin/env bash
# sh organization-new-acc.sh --account_name htl-test-sub-11 --account_email dimdung108@gmail.com --cl_profile_name dimdung1
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------
# Note: This script can be used to create AWS new account using AWS Organization, Bootstrap account from the screatch ( creates all the resoruces using CFT)
# 1. In order to create an account, you must sign in to your organization’s master account with a minimum of the following permissions:
#   - organizations:DescribeOrganization
#   - organizations:CreateAccount
# 2. Person executing this script should have an access for Master Prayer account and workspace VPC ...
# 3.

function usage
{
    echo "usage: organization_new_acc.sh [-h] --account_name ACCOUNT_NAME
                                      --account_email ACCOUNT_EMAIL
                                      --cl_profile_name CLI_PROFILE_NAME
                                      [--ou_name ORGANIZATION_UNIT_NAME]
                                      [--region AWS_REGION]"
}

newAccName=""
newAccEmail=""
newProfile=""
roleName="OrganizationAccountAccessRole"
destinationOUname=""
accountAlias="htl-test-sub-11"
stackName="htl-lob-infraeng"
# Parameters
environmentName="InfraEng"
MsAd4Dhcp="false"
region="us-east-1"

while [ "$1" != "" ]; do
    case $1 in
        -n | --account_name )   shift
                                newAccName=$1
                                ;;
        -e | --account_email )  shift
                                newAccEmail=$1
                                ;;
        -p | --cl_profile_name ) shift
                                newProfile=$1
                                ;;
        -o | --ou_name )        shift
                                destinationOUname=$1
                                ;;
        -r | --region )        shift
                                region=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
    esac
    shift
done

if [ "$newAccName" = "" ] || [ "$newAccEmail" = "" ] || [ "$newProfile" = "" ]
then
  usage
  exit
fi
# Creating New AWS LAB Account
printf "Creating AWS New LAB/Test Account\n"
ReqID=$(aws organizations create-account --email $newAccEmail --account-name "$newAccName" --role-name $roleName \
--query 'CreateAccountStatus.[Id]' \
--output text)

printf "Waiting for New Account ..."
orgStat=$(aws organizations describe-create-account-status --create-account-request-id $ReqID \
--query 'CreateAccountStatus.[State]' \
--output text)

while [ $orgStat != "SUCCEEDED" ]
do
  if [ $orgStat = "FAILED" ]
  then
    printf "\nAccount Failed to Create\n"
    exit 1
  fi
  printf "."
  sleep 10
  orgStat=$(aws organizations describe-create-account-status --create-account-request-id $ReqID \
  --query 'CreateAccountStatus.[State]' \
  --output text)
done

accID=$(aws organizations describe-create-account-status --create-account-request-id $ReqID \
--query 'CreateAccountStatus.[AccountId]' \
--output text)

accARN="arn:aws:iam::$accID:role/$roleName"

# Setting up New CLI Profiles
printf "\nCreating New CLI Profile....\n"
aws configure set region $region --profile $newProfile
aws configure set role_arn $accARN --profile $newProfile
aws configure set source_profile default --profile $newProfile

cfcntr=0
printf "Waiting for CF Service ..."
aws cloudformation list-stacks --profile $newProfile > /dev/null 2>&1
actOut=$?
while [[ $actOut -ne 0 && $cfcntr -le 10 ]]
do
  sleep 5
  aws cloudformation list-stacks --profile $newProfile > /dev/null 2>&1
  actOut=$?
  if [ $actOut -eq 0 ]
  then
    break
  fi
  printf "."
  cfcntr=$[$cfcntr +1]
done

if [ $cfcntr -gt 10 ]
then
  printf "\nCF Service not available\n"
  exit 1
fi

# Creatin IAM Alias for new Account
aws iam create-account-alias --account-alias $accountAlias --profile $newProfile

# Authorization of AWS Lambda Functions for Newly creatd Account
## Adding permision for htlGetIpAddress
aws lambda add-permission \
  --function-name htlGetIpAddress \
  --region $region \
  --statement-id Id-$accID \
  --action "lambda:InvokeFunction" \
  --principal $accID \
  --profile default

 ## Adding permision for CidrFinder
 aws lambda add-permission \
   --function-name cidr-findr-Function-105ZI6EX2XHW8 \
   --region $region \
   --statement-id Id-$accID \
   --action "lambda:InvokeFunction" \
   --principal $accID \
   --profile default
   #--profile htlcloudacn9
# Get the htl-iam-crossaccount-vpcpeering.yaml file in your working directory
printf "\nDownloading htl-iam-crossaccount-vpcpeering.yaml file from S3..."
aws s3 cp s3://htl-infosec-testlab-artifacts/htl-iam-crossaccount-vpcpeering.yaml .

# Updated Assume Role Policy in WS (Workspace) account to enable VPC Peering with Newly created account
printf "\nUpdting crossaccount VPC perring Roles in Workspace VPC/Account\n"
# ------------------------------------------------------------------------------
#newaccid=$(aws sts get-caller-identity --profile htlcloudacn9 --query 'Account' --output text)
sed '15i  \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ - !Sub 'arn:aws:iam::$accID:root'' htl-iam-crossaccount-vpcpeering.yaml > ttt.yaml

# Uploade the file into the S3
printf "\nUploading file to S3 htl-infosec-testlab-artifacts ...."
aws s3 cp ttt.yaml s3://htl-infosec-testlab-artifacts/htl-iam-crossaccount-vpcpeering.yaml --acl public-read > /dev/null

# Updating CFT templates using S3 Bucket templates URLs
printf "\nUpdating CFT for VPC Peering "
aws cloudformation update-stack --stack-name CF-VPCPeering --template-url https://s3.us-east-1.amazonaws.com/htl-infosec-testlab-artifacts/htl-iam-crossaccount-vpcpeering.yaml \
 --profile htlcloudacn11 --region $region --capabilities CAPABILITY_NAMED_IAM

sleep 30

## Creating VPC Under New Account
printf "\nCreating VPC Under New Account\n"
aws cloudformation create-stack --stack-name $stackName --template-url https://s3.us-east-1.amazonaws.com/htl-infosec-testlab-artifacts/htl-vpc-final-v1.yaml \
--parameters ParameterKey=EnvironmentName,ParameterValue=$environmentName ParameterKey=HasMSAD,ParameterValue=$MsAd4Dhcp --capabilities CAPABILITY_NAMED_IAM \
--region $region --profile $newProfile > /dev/null 2>&1

if [ $? -ne 0 ]
then
  printf "CF VPC Stack Failed to Create\n"
  exit 1
fi

printf "Waiting for CF Stack to Finish ..."
cfStat=$(aws cloudformation describe-stacks --stack-name $stackName --region $region  --profile $newProfile --query 'Stacks[0].[StackStatus]' --output text)
while [ $cfStat != "CREATE_COMPLETE" ]
do
  sleep 5
  printf "."
  cfStat=$(aws cloudformation describe-stacks --stack-name $stackName --region $region  --profile $newProfile --query 'Stacks[0].[StackStatus]' --output text)
  if [ $cfStat = "CREATE_FAILED" ]
  then
    printf "\nVPC Failed to Create\n"
    exit 1
  fi
done
printf "\nVPC Created Under New Account\n"


# Okta IDP Creation

# Get the okta-dev.xml file in your working directory
printf "\nDownloading okta-dev.xml  file from S3..."
aws s3 cp s3://htl-infosec-testlab-artifacts/okta-prod.xml .

printf "Creating IDP for Okta Under New Account\n"
#aws iam create-saml-provider --saml-metadata-document file://okta-dev.xml --name MultiAcct --profile $newProfile
aws iam create-saml-provider --saml-metadata-document file://okta-prod.xml  --name MultiAcct-Prod --profile $newProfile
if [ $? -eq 0 ]
then
  printf "Okta IDP Created .."
else
  printf "Okta IDP Creation Failed"