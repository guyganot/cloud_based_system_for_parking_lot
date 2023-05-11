#!/bin/bash

# Generate a new key pair for EC2 instance access
KEY_NAME="parking-lot-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "Creating key pair $KEY_NAME to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# Secure the key pair
chmod 400 $KEY_PEM

# Create a new security group for the instance with inbound rules for SSH and HTTP traffic
SEC_GRP="parking-lot-sg-`date +'%N'`"
echo "Setting up security group $SEC_GRP"
aws ec2 create-security-group \
    --group-name $SEC_GRP \
    --description "Access parking lot instances"

# Get the user's public IP address to restrict SSH access to the instance
MY_IP=$(curl ipinfo.io/ip)

# Add inbound rules for SSH and HTTP traffic
echo "Setting up SSH rule allowing access only from $MY_IP"
aws ec2 authorize-security-group-ingress \
    --group-name $SEC_GRP --protocol tcp --port 22 \
    --cidr $MY_IP/32

echo "Setting up HTTP rule allowing access from any IP"
aws ec2 authorize-security-group-ingress \
    --group-name $SEC_GRP --protocol tcp --port 80 \
    --cidr 0.0.0.0/0

# Get the ID of the latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --filters "Name=name,Values=amzn2-ami-hvm-2.0.????????.?-x86_64-gp2" \
    --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" \
    --output text)

# Launch a new EC2 instance with the created key pair and security group
echo "Creating EC2 instance"
RUN_INSTANCES=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --key-name $KEY_NAME \
    --security-group-ids $SEC_GRP \
    --user-data file://startup.sh)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | jq -r '.Reservations[0].Instances[0].PublicIpAddress')

echo "New instance $INSTANCE_ID @ $PUBLIC_IP"

# Deploy the Flask application to the instance and start it using systemd
echo "Deploying application to instance"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" app.py ubuntu@$PUBLIC_IP:/home/ubuntu/
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" systemd/parking-lot.service ubuntu@$PUBLIC_IP:/home/ubuntu/

echo "Setting up application environment on instance"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" ubuntu@$PUBLIC_IP << EOF
    sudo apt update
    sudo apt install -y python3-pip
    sudo pip3 install flask
    sudo mv /home/ubuntu/parking-lot.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable parking-lot.service
    sudo systemctl start parking-lot.service
EOF
