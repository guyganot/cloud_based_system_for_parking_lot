KEY_NAME="cloud-course-`date +'%N'`"
KEY_PEM="$KEY_NAME.pem"

echo "create key pair $KEY_PEM to connect to instances and save locally"
aws ec2 create-key-pair --key-name $KEY_NAME \
    | jq -r ".KeyMaterial" > $KEY_PEM

# secure the key pair
chmod 400 $KEY_PEM

SEC_GRP="my-sg-`date +'%N'`"

echo "setup firewall $SEC_GRP"
aws ec2 create-security-group   \
    --group-name $SEC_GRP       \
    --description "Access my instances" 

# figure out my ip
MY_IP=$(curl ipinfo.io/ip)
echo "My IP: $MY_IP"


echo "Setup rule allowing SSH access to $MY_IP only"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 22 --protocol tcp --cidr "$MY_IP"/32

echo "Setup rule allowing HTTP (port 5000) access to $MY_IP only"
aws ec2 authorize-security-group-ingress --group-name "$SEC_GRP" --port 5000 --protocol tcp --cidr "$MY_IP"/32

UBUNTU_20_04_AMI="ami-00aa9d3df94c6c354"

echo "Creating Ubuntu 20.04 instance..."
RUN_INSTANCES=$(aws ec2 run-instances   \
    --image-id $UBUNTU_20_04_AMI        \
    --instance-type t2.micro            \
    --key-name $KEY_NAME                \
    --security-groups $SEC_GRP)

INSTANCE_ID=$(echo $RUN_INSTANCES | jq -r '.Instances[0].InstanceId')

echo "Waiting for instance creation..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

PUBLIC_IP=$(aws ec2 describe-instances  --instance-ids $INSTANCE_ID | 
    jq -r '.Reservations[0].Instances[0].PublicIpAddress'
)

echo "New instance $INSTANCE_ID @ $PUBLIC_IP"

echo "deploying code to production"
scp -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=60" main.py ubuntu@$PUBLIC_IP:/home/ubuntu/

echo "setup production environment"
ssh -i $KEY_PEM -o "StrictHostKeyChecking=no" -o "ConnectionAttempts=10" ubuntu@$PUBLIC_IP <<EOF
    sudo apt update
    sudo apt install python3-flask -y
    sudo apt-get install jq
    sudo snap install docker         # version 20.10.24, or
    sudo snap install docker         # version 20.10.17
    sudo apt  install docker.io      # version 20.10.21-0ubuntu1~22.04.3
    sudo apt  install podman-docker  # version 3.4.4+ds1-1ubuntu1
    export FLASK_APP="main.py"
    # run app
    nohup flask run --host 0.0.0.0  &>/dev/null &
    exit
EOF

echo
echo "This is the IP of the Current instance: $PUBLIC_IP"
echo
echo "Example for insert a car: curl -X POST http://$PUBLIC_IP:22/entry?plate=123-123-123&parkingLot=382"
echo
curl --ipv4 -X POST "http://$PUBLIC_IP:22/entry?plate=123-123-123&parkingLot=382"
echo
echo "Example for exit that car curl -X POST http://$PUBLIC_IP:5000/exit?ticketId=0"
echo
curl --ipv4 -X POST "http://$PUBLIC_IP:5000/exit?ticketId=0"
