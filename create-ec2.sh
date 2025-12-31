#!/bin/bash

# EC2 Instance Creation Script for InstaRepay Deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 EC2 Instance Creation for InstaRepay${NC}"
echo -e "${BLUE}=========================================${NC}"

# Configuration
INSTANCE_TYPE="t3.micro"
REGION="us-east-1"
AMI_ID="ami-0e86e20dae9224db8"  # Ubuntu 22.04 LTS in us-east-1
KEY_NAME="instarepay-key"
SECURITY_GROUP_NAME="instarepay-sg"

# Check if key pair exists
echo -e "${BLUE}🔍 Checking for existing key pair...${NC}"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Key pair '$KEY_NAME' already exists${NC}"
else
    echo -e "${YELLOW}Creating key pair '$KEY_NAME'...${NC}"
    aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_NAME.pem"
    chmod 400 "$KEY_NAME.pem"
    echo -e "${GREEN}✅ Key pair created and saved as '$KEY_NAME.pem'${NC}"
fi

# Check if security group exists
echo -e "${BLUE}🔍 Checking for existing security group...${NC}"
SG_ID=$(aws ec2 describe-security-groups --group-names "$SECURITY_GROUP_NAME" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo -e "${GREEN}✅ Security group '$SECURITY_GROUP_NAME' already exists (ID: $SG_ID)${NC}"
else
    echo -e "${YELLOW}Creating security group '$SECURITY_GROUP_NAME'...${NC}"
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for InstaRepay application" \
        --query 'GroupId' \
        --output text)

    # Add inbound rules
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 3000 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 3001 --cidr 0.0.0.0/0

    echo -e "${GREEN}✅ Security group created (ID: $SG_ID)${NC}"
fi

# Launch EC2 instance
echo -e "${BLUE}🚀 Launching EC2 instance...${NC}"

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=InstaRepay-Prod}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✅ EC2 instance launched (ID: $INSTANCE_ID)${NC}"

# Wait for instance to be running
echo -e "${BLUE}⏳ Waiting for instance to be running...${NC}"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0]')
PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress')

echo ""
echo -e "${GREEN}🎉 EC2 Instance Ready!${NC}"
echo -e "${GREEN}============================${NC}"
echo -e "Instance ID: ${INSTANCE_ID}"
echo -e "Public IP: ${PUBLIC_IP}"
echo -e "Region: ${REGION}"
echo -e "Key Pair: ${KEY_NAME}.pem"
echo ""

# Create aws.pem symlink for deployment script
if [ -f "${KEY_NAME}.pem" ]; then
    ln -sf "${KEY_NAME}.pem" aws.pem
    echo -e "${GREEN}✅ Created symlink: aws.pem -> ${KEY_NAME}.pem${NC}"
fi

echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "1. Wait a few minutes for the instance to fully initialize"
echo "2. Test SSH connection: ssh -i aws.pem ubuntu@${PUBLIC_IP}"
echo "3. Deploy your app: ./aws-deploy.sh -i ${INSTANCE_ID}"
echo ""
echo -e "${YELLOW}⚠️  Remember to stop the instance when not in use to avoid charges!${NC}"
echo -e "${YELLOW}   aws ec2 stop-instances --instance-ids ${INSTANCE_ID}${NC}"
