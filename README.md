# InstaRepay Infrastructure

This repository contains the infrastructure code, deployment scripts, and configurations for the InstaRepay application deployed across separate AWS services.

## Architecture Overview

```
├── 🎨 Frontend (AWS Amplify)
│   ├── Repository: https://github.com/MohammedBr0/instarepay-frontend
│   ├── Environment: Static hosting with CDN
│   └── URL: https://your-app.amplifyapp.com
│
├── 🔧 Backend (AWS EC2)
│   ├── Repository: https://github.com/MohammedBr0/instarepay-backend
│   ├── Staging: i-03698282fa4691fe2 (54.82.73.189)
│   ├── Production: i-0cd72f739971ae8d2 (54.82.139.147)
│   └── API: http://instance-ip:3001
│
└── 🏗️ Infrastructure (This repo)
    ├── Deployment scripts and configurations
    ├── AWS resource management
    └── Cross-service orchestration
```

## Current AWS Resources

### EC2 Instances
- **Backend Staging**: `i-03698282fa4691fe2` - `54.82.73.189`
- **Backend Production**: `i-0cd72f739971ae8d2` - `54.82.139.147`

### Security Groups
- **Backend Staging**: `sg-0a140fabb77dfe472`
- **Backend Production**: `sg-0f9591461b3d70fe6`

### Key Pairs
- **Backend**: `instarepay-backend-key.pem`

## Quick Start

### 1. Test Backend Instances
```bash
# Test staging instance
ssh -i backend.pem ubuntu@54.82.73.189

# Test production instance
ssh -i backend.pem ubuntu@54.82.139.147
```

### 2. Deploy Backend (Manual)
```bash
# Deploy to staging
./scripts/deploy-backend.sh staging ghcr.io/MohammedBr0/instarepay-backend:latest

# Deploy to production
./scripts/deploy-backend.sh production ghcr.io/MohammedBr0/instarepay-backend:latest
```

### 3. Create Additional Resources
```bash
# Create new staging instance
./create-backend-ec2.sh staging

# Create new production instance
./create-backend-ec2.sh production
```

## Repository Structure

```
├── scripts/
│   ├── deploy-backend.sh      # Backend deployment script
│   └── deploy-ci.sh          # Legacy CI deployment script
├── .github/
│   └── workflows/            # Infrastructure CI/CD (if needed)
├── docker-compose.prod.yml   # Production Docker Compose
├── .env.production          # Production environment variables
├── create-backend-ec2.sh     # EC2 instance creation script
├── aws-deploy.sh            # Legacy deployment script
└── create-ec2.sh            # Legacy EC2 creation script
```

## Environment Variables

### Backend Production (.env.production)
```bash
# Database
DATABASE_URL=postgresql://...

# JWT
JWT_SECRET=your-production-secret
JWT_EXPIRES_IN=24h

# Stripe
STRIPE_SECRET_KEY=sk_live_...
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_WEBHOOK_SECRET=whsec_...

# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password

# AWS
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret

# Application
NODE_ENV=production
PORT=3001
```

## Deployment Workflow

### Backend Deployment
1. **Push to GitHub** → Triggers CI/CD pipeline
2. **Run Tests** → Automated testing suite
3. **Build Docker Image** → Push to GitHub Container Registry
4. **Deploy to EC2** → Update running containers
5. **Health Check** → Verify deployment success

### Frontend Deployment
1. **Push to GitHub** → Connects to AWS Amplify
2. **Amplify Build** → Static site generation
3. **CDN Deployment** → Global content distribution
4. **Custom Domain** → Optional domain configuration

## Monitoring & Maintenance

### Check Instance Status
```bash
# List all instances
aws ec2 describe-instances --filters "Name=tag:Name,Values=InstaRepay*" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' --output table

# Check instance health
ssh -i backend.pem ubuntu@instance-ip 'docker ps'
```

### Logs & Debugging
```bash
# Backend logs
ssh -i backend.pem ubuntu@instance-ip 'docker logs instarepay-backend'

# System logs
ssh -i backend.pem ubuntu@instance-ip 'tail -f /var/log/syslog'
```

### Cost Management
```bash
# Stop instances when not in use
aws ec2 stop-instances --instance-ids i-03698282fa4691fe2 i-0cd72f739971ae8d2

# Start instances when needed
aws ec2 start-instances --instance-ids i-03698282fa4691fe2 i-0cd72f739971ae8d2
```

## Security Best Practices

- ✅ Separate security groups for staging/production
- ✅ SSH key-based authentication
- ✅ Environment-specific secrets
- ✅ Minimal open ports (22, 80, 443, 3001)
- ✅ Regular key rotation
- ✅ Network isolation

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   chmod 400 backend.pem
   ssh -i backend.pem ubuntu@instance-ip
   ```

2. **Deployment Failed**
   ```bash
   # Check instance resources
   ssh -i backend.pem ubuntu@instance-ip 'df -h && free -h'

   # Check Docker status
   ssh -i backend.pem ubuntu@instance-ip 'docker ps -a'
   ```

3. **Application Not Responding**
   ```bash
   # Check application logs
   ssh -i backend.pem ubuntu@instance-ip 'docker logs instarepay-backend'

   # Check port availability
   ssh -i backend.pem ubuntu@instance-ip 'netstat -tlnp | grep 3001'
   ```

## Next Steps

1. **Set up AWS Amplify** for frontend deployment
2. **Configure GitHub Secrets** for automated deployments
3. **Set up monitoring** (CloudWatch, health checks)
4. **Configure custom domains** for production
5. **Set up backup strategies** for databases
6. **Implement auto-scaling** based on load

## Support

For issues with infrastructure:
1. Check AWS Console for resource status
2. Review deployment logs in GitHub Actions
3. Check instance system logs
4. Verify environment variables and secrets
