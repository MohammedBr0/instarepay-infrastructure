#!/bin/bash

# CI/CD Deployment Script for InstaRepay
# This script is called by GitHub Actions for automated deployments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENVIRONMENT=${1:-"staging"}
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EC2_INSTANCE_ID=""
EC2_PUBLIC_IP=""
REGION="us-east-1"
REMOTE_USER="ubuntu"
APP_DIR="/opt/instarepay"

echo -e "${BLUE}🚀 InstaRepay CI/CD Deployment (${ENVIRONMENT})${NC}"
echo -e "${BLUE}=======================================${NC}"

# Get instance details based on environment
get_instance_details() {
    echo -e "${BLUE}🔍 Getting ${ENVIRONMENT} instance details...${NC}"

    local tag_name
    if [ "$ENVIRONMENT" = "production" ]; then
        tag_name="InstaRepay-Prod"
    else
        tag_name="InstaRepay-Staging"
    fi

    INSTANCE_INFO=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=tag:Name,Values=$tag_name" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0]' \
        --output json)

    EC2_PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress')
    EC2_INSTANCE_ID=$(echo "$INSTANCE_INFO" | jq -r '.InstanceId')

    if [ -z "$EC2_PUBLIC_IP" ] || [ "$EC2_PUBLIC_IP" = "null" ]; then
        echo -e "${RED}❌ No ${ENVIRONMENT} instance found${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ ${ENVIRONMENT} instance $EC2_INSTANCE_ID is running at $EC2_PUBLIC_IP${NC}"
}

# Deploy using Docker images from GitHub Container Registry
deploy_with_containers() {
    echo -e "${BLUE}🐳 Deploying with container images...${NC}"

    # Get the latest image tags
    FRONTEND_IMAGE="ghcr.io/${GITHUB_REPOSITORY}/frontend:$(git rev-parse --short HEAD)"
    BACKEND_IMAGE="ghcr.io/${GITHUB_REPOSITORY}/backend:$(git rev-parse --short HEAD)"

    if [ "$GITHUB_REF" = "refs/heads/main" ]; then
        FRONTEND_IMAGE="ghcr.io/${GITHUB_REPOSITORY}/frontend:latest"
        BACKEND_IMAGE="ghcr.io/${GITHUB_REPOSITORY}/backend:latest"
    fi

    # SSH deployment commands
    DEPLOY_COMMANDS="
        set -e
        echo 'Setting up deployment directory...'
        sudo mkdir -p $APP_DIR
        sudo chown ubuntu:ubuntu $APP_DIR
        cd $APP_DIR

        echo 'Pulling latest container images...'
        docker pull $FRONTEND_IMAGE
        docker pull $BACKEND_IMAGE

        echo 'Stopping existing containers...'
        docker-compose -f docker-compose.prod.yml down || true

        echo 'Starting new deployment...'
        sed -i 's|image:.*frontend.*|image: $FRONTEND_IMAGE|g' docker-compose.prod.yml
        sed -i 's|image:.*backend.*|image: $BACKEND_IMAGE|g' docker-compose.prod.yml

        echo 'Starting services...'
        docker-compose -f docker-compose.prod.yml up -d

        echo 'Waiting for services to be healthy...'
        sleep 30

        echo 'Checking service health...'
        docker-compose -f docker-compose.prod.yml ps

        echo 'Running database migrations if needed...'
        docker-compose -f docker-compose.prod.yml exec -T backend npm run migrate:prod || true

        echo 'Deployment completed successfully!'
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
    deploy_with_containers

    echo -e "${GREEN}✅ ${ENVIRONMENT} deployment completed successfully!${NC}"
    echo -e "${GREEN}🌐 Application URL: http://$EC2_PUBLIC_IP${NC}"
    echo -e "${GREEN}🔌 API URL: http://$EC2_PUBLIC_IP/api${NC}"

    if [ "$ENVIRONMENT" = "production" ]; then
        echo -e "${YELLOW}🚨 Production deployment completed - please verify the application${NC}"
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

main
