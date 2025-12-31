#!/bin/bash

# AWS CLI Deployment Script for InstaRepay
# This script handles complete AWS EC2 deployment using AWS CLI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EC2_INSTANCE_ID=""
EC2_PUBLIC_IP=""
REGION=""
SSH_KEY_PATH="aws.pem"
REMOTE_USER="ubuntu"
APP_DIR="/opt/instarepay"

# Function to check AWS CLI and credentials
check_aws_setup() {
    echo -e "${BLUE}🔍 Checking AWS CLI setup...${NC}"

    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS CLI is not installed. Please install it first.${NC}"
        exit 1
    fi

    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo -e "${RED}❌ AWS credentials not configured.${NC}"
        echo -e "${YELLOW}Please run: aws configure${NC}"
        echo -e "${YELLOW}Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ AWS CLI and credentials are configured${NC}"
}

# Function to get EC2 instance details
get_ec2_details() {
    echo -e "${BLUE}🔍 Getting EC2 instance details...${NC}"

    if [ -z "$EC2_INSTANCE_ID" ]; then
        echo -e "${YELLOW}Enter your EC2 instance ID:${NC}"
        read -r EC2_INSTANCE_ID
    fi

    # Get instance details
    INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" ${REGION:+--region $REGION} --query 'Reservations[0].Instances[0]' --output json)

    EC2_PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIpAddress')
    EC2_STATE=$(echo "$INSTANCE_INFO" | jq -r '.State.Name')

    if [ "$EC2_STATE" != "running" ]; then
        echo -e "${RED}❌ EC2 instance is not running (current state: $EC2_STATE)${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ EC2 instance $EC2_INSTANCE_ID is running at $EC2_PUBLIC_IP${NC}"
}

# Function to upload files to EC2
upload_to_ec2() {
    echo -e "${BLUE}📤 Uploading application files to EC2...${NC}"

    # Create temporary directory for deployment
    DEPLOY_TEMP="/tmp/instarepay-deploy-$(date +%s)"
    mkdir -p "$DEPLOY_TEMP"

    # Copy necessary files
    cp -r "$PROJECT_ROOT" "$DEPLOY_TEMP/"
    cd "$DEPLOY_TEMP"

    # Remove unnecessary files
    rm -rf InstaRepay-frontend/node_modules
    rm -rf loan-management-backend/node_modules
    rm -rf InstaRepay-frontend/.next
    rm -rf */*.log

    # Create tarball
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    TAR_FILE="instarepay-deploy-${TIMESTAMP}.tar.gz"
    tar -czf "$TAR_FILE" -C "$PROJECT_ROOT" .

    # Upload to EC2
    echo -e "${BLUE}Uploading $TAR_FILE to EC2...${NC}"
    scp -i "$PROJECT_ROOT/$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$TAR_FILE" "$REMOTE_USER@$EC2_PUBLIC_IP:/tmp/"

    # Clean up
    rm -rf "$DEPLOY_TEMP"

    echo -e "${GREEN}✅ Files uploaded successfully${NC}"

    # Return the tar file name for remote operations
    echo "$TAR_FILE"
}

# Function to run deployment on EC2
deploy_on_ec2() {
    TAR_FILE=$1

    echo -e "${BLUE}🚀 Starting deployment on EC2...${NC}"

    # SSH commands to execute on EC2
    SSH_CMD="
        set -e
        echo 'Updating system...'
        sudo apt update && sudo apt upgrade -y

        echo 'Installing prerequisites...'
        sudo apt install -y curl wget git unzip

        echo 'Installing Docker if not present...'
        if ! command -v docker >/dev/null 2>&1; then
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
        fi

        echo 'Installing Docker Compose if not present...'
        if ! command -v docker-compose >/dev/null 2>&1; then
            sudo curl -L 'https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-\$(uname -s)-\$(uname -m)' -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        fi

        echo 'Setting up application directory...'
        sudo mkdir -p $APP_DIR
        sudo chown ubuntu:ubuntu $APP_DIR
        cd $APP_DIR

        echo 'Extracting deployment files...'
        tar -xzf /tmp/$TAR_FILE -C $APP_DIR --strip-components=1

        echo 'Making scripts executable...'
        chmod +x deploy.sh update.sh rollback.sh

        echo 'Checking environment files...'
        if [ ! -f '.env.production' ]; then
            echo 'Warning: .env.production not found. Please ensure environment variables are set.'
        fi

        echo 'Starting deployment...'
        ./deploy.sh
    "

    # Execute deployment on EC2
    ssh -i "$PROJECT_ROOT/$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$EC2_PUBLIC_IP" "$SSH_CMD"

    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo -e "${GREEN}📱 Application URL: http://$EC2_PUBLIC_IP${NC}"
    echo -e "${GREEN}🔌 API URL: http://$EC2_PUBLIC_IP/api${NC}"
}

# Function to setup SSL (optional)
setup_ssl() {
    echo -e "${BLUE}🔒 Setting up SSL certificate...${NC}"

    SSL_CMD="
        sudo apt install -y certbot python3-certbot-nginx
        echo 'SSL setup requires domain name. Please run manually:'
        echo 'sudo certbot --nginx -d your-domain.com'
    "

    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$REMOTE_USER@$EC2_PUBLIC_IP" "$SSL_CMD"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "AWS EC2 Deployment Script for InstaRepay"
    echo ""
    echo "OPTIONS:"
    echo "  -i, --instance-id ID    EC2 instance ID (required)"
    echo "  -k, --key-path PATH     SSH key path (default: aws.pem)"
    echo "  -u, --user USER         SSH username (default: ubuntu)"
    echo "  -r, --region REGION    AWS region of the EC2 instance (e.g. eu-north-1)"
    echo "  --ssl                   Setup SSL certificate after deployment"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -i i-1234567890abcdef0"
    echo "  $0 -i i-1234567890abcdef0 -k ~/.ssh/my-key.pem --ssl"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--instance-id)
            EC2_INSTANCE_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -k|--key-path)
            SSH_KEY_PATH="$2"
            shift 2
            ;;
        -u|--user)
            REMOTE_USER="$2"
            shift 2
            ;;
        --ssl)
            SETUP_SSL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo -e "${GREEN}🚀 InstaRepay AWS EC2 Deployment${NC}"
    echo -e "${GREEN}=================================${NC}"

    check_aws_setup
    get_ec2_details

    TAR_FILE=$(upload_to_ec2)
    deploy_on_ec2 "$TAR_FILE"

    if [ "$SETUP_SSL" = true ]; then
        setup_ssl
    fi

    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Configure your domain DNS to point to $EC2_PUBLIC_IP"
    echo "2. Run SSL setup if needed: ./aws-deploy.sh --ssl"
    echo "3. Monitor logs: ssh -i aws.pem $REMOTE_USER@$EC2_PUBLIC_IP 'cd $APP_DIR && docker-compose -f docker-compose.prod.yml logs -f'"
}

# Check if instance ID is provided
if [ -z "$EC2_INSTANCE_ID" ]; then
    echo -e "${RED}❌ EC2 instance ID is required.${NC}"
    echo ""
    usage
    exit 1
fi

# Check if SSH key exists
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ SSH key not found at $SSH_KEY_PATH${NC}"
    echo -e "${YELLOW}Please ensure aws.pem exists in the current directory or specify the correct path with -k option${NC}"
    exit 1
fi

main
