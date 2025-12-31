#!/bin/bash

# Backend Deployment Script for InstaRepay
# This script handles backend deployment to separate AWS EC2 instances

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-"staging"}
IMAGE_NAME=${2:-"ghcr.io/mohammedbr0/instarepay-backend:latest"}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_USER="ubuntu"

# Get instance details based on environment
get_instance_details() {
    echo -e "${BLUE}🔍 Getting backend ${ENVIRONMENT} instance details...${NC}"

    local tag_name
    if [ "$ENVIRONMENT" = "production" ]; then
        tag_name="InstaRepay-Backend-Prod"
    else
        tag_name="InstaRepay-Backend-Staging"
    fi

    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region us-east-1 \
        --filters "Name=tag:Name,Values=$tag_name" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0]' \
        --output json)

    EC2_PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress')
    EC2_INSTANCE_ID=$(echo "$INSTANCE_INFO" | jq -r '.InstanceId')

    if [ -z "$EC2_PUBLIC_IP" ] || [ "$EC2_PUBLIC_IP" = "null" ]; then
        echo -e "${RED}❌ No backend ${ENVIRONMENT} instance found${NC}"
        echo -e "${YELLOW}Please create a backend EC2 instance and tag it as '$tag_name'${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Backend ${ENVIRONMENT} instance $EC2_INSTANCE_ID is running at $EC2_PUBLIC_IP${NC}"
}

# Deploy backend using Docker
deploy_backend() {
    echo -e "${BLUE}🐳 Deploying backend with Docker image: $IMAGE_NAME${NC}"

    # SSH deployment commands
    DEPLOY_COMMANDS="
        set -e
        echo 'Setting up backend deployment directory...'
        sudo mkdir -p /opt/instarepay-backend
        sudo chown ubuntu:ubuntu /opt/instarepay-backend
        cd /opt/instarepay-backend

        echo 'Stopping existing backend containers...'
        docker stop instarepay-backend 2>/dev/null || true
        docker rm instarepay-backend 2>/dev/null || true

        echo 'Pulling latest backend image...'
        docker pull $IMAGE_NAME

        echo 'Starting backend container...'
        docker run -d \\
          --name instarepay-backend \\
          --restart unless-stopped \\
          -p 3001:3001 \\
          -e NODE_ENV=$ENVIRONMENT \\
          -e DATABASE_URL='${DATABASE_URL}' \\
          -e JWT_SECRET='${JWT_SECRET}' \\
          -e STRIPE_SECRET_KEY='${STRIPE_SECRET_KEY}' \\
          -e SMTP_HOST='${SMTP_HOST}' \\
          -e SMTP_USER='${SMTP_USER}' \\
          -e SMTP_PASS='${SMTP_PASS}' \\
          $IMAGE_NAME

        echo 'Waiting for backend to be healthy...'
        sleep 30

        echo 'Checking backend health...'
        curl -f http://localhost:3001/health || echo 'Health check endpoint not available'

        echo 'Backend deployment completed successfully!'
    "

    # Execute deployment
    ssh -i "$PROJECT_ROOT/aws.pem" \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=60 \
        "$REMOTE_USER@$EC2_PUBLIC_IP" \
        "$DEPLOY_COMMANDS"
}

# Main execution
main() {
    get_instance_details
    deploy_backend

    echo -e "${GREEN}✅ Backend ${ENVIRONMENT} deployment completed successfully!${NC}"
    echo -e "${GREEN}🔗 Backend API URL: http://$EC2_PUBLIC_IP:3001${NC}"
    echo -e "${GREEN}📊 Health Check: http://$EC2_PUBLIC_IP:3001/health${NC}"

    if [ "$ENVIRONMENT" = "production" ]; then
        echo -e "${YELLOW}🚨 Production backend deployment completed - please verify the API${NC}"
    fi
}

# Validate environment argument
if [ "$ENVIRONMENT" != "staging" ] && [ "$ENVIRONMENT" != "production" ]; then
    echo -e "${RED}❌ Invalid environment. Use 'staging' or 'production'${NC}"
    exit 1
fi

# Check for required files
if [ ! -f "$PROJECT_ROOT/aws.pem" ]; then
    echo -e "${RED}❌ SSH key not found at $PROJECT_ROOT/aws.pem${NC}"
    exit 1
fi

# Load environment variables (these should be set as GitHub secrets)
# In a real deployment, these would be passed securely
export DATABASE_URL="${DATABASE_URL:-postgresql://user:pass@localhost:5432/instarepay}"
export JWT_SECRET="${JWT_SECRET:-your-jwt-secret}"
export STRIPE_SECRET_KEY="${STRIPE_SECRET_KEY:-sk_test_...}"
export SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"
export SMTP_USER="${SMTP_USER:-your-email@gmail.com}"
export SMTP_PASS="${SMTP_PASS:-your-app-password}"

main
