#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
SG_ID="sg-016466050ba240b84" # Allow all traffic SG ID
ZONE_ID="Z071722410SPRZ7TY4PCQ" # AWS Route53 hosted zone ID
DOMAIN_NAME="rahuldaws.store" # Roboshop website DNS

for instance in "$@"
do
    # Check if instance already exists
    INSTANCE_ID=$(aws ec2 describe-instances \
        --filters \
        "Name=tag:Name,Values=$instance" \
        "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)

    if [ -z "$INSTANCE_ID" ]
    then
        echo "$instance instance does not exist. Creating..."

        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --instance-type t2.micro \
            --security-group-ids "$SG_ID" \
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instance}]" \
            --query "Instances[0].InstanceId" \
            --output text)

        echo "$instance instance created: $INSTANCE_ID"

        # Wait until instance is running
        aws ec2 wait instance-running \
            --instance-ids "$INSTANCE_ID"

    else
        echo "$instance instance already exists: $INSTANCE_ID"
    fi

    if [ "$instance" != "frontend" ]
    then
        IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].PrivateIpAddress" \
            --output text)

        RECORD_NAME="$instance.$DOMAIN_NAME"

    else
        IP=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].PublicIpAddress" \
            --output text)

        RECORD_NAME="$DOMAIN_NAME"
    fi

    echo "$instance IP address: $IP"

    aws route53 change-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --change-batch '{
            "Comment": "Creating or Updating a record set",
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "'"$RECORD_NAME"'",
                    "Type": "A",
                    "TTL": 1,
                    "ResourceRecords": [{
                        "Value": "'"$IP"'"
                    }]
                }
            }]
        }'

done