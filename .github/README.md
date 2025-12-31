# InstaRepay CI/CD Pipeline

This repository uses GitHub Actions for continuous integration and deployment with a main/dev branch strategy.

## Branch Strategy

### Branches
- **`main`** - Production branch. All deployments to production come from this branch.
- **`dev`** - Development branch. Deployments go to staging environment.

### Workflow
1. **Development**: Work on feature branches, merge to `dev` for staging testing
2. **Staging**: `dev` branch deploys to staging environment automatically
3. **Production**: Create PR from `dev` to `main`, merge triggers production deployment

## Setup Instructions

### 1. Repository Setup

```bash
# Create and switch to dev branch
git checkout -b dev
git push -u origin dev

# Set up branch protection rules (GitHub UI)
# Go to Settings > Branches > Add rule
# - Branch name pattern: main
# - Require pull request reviews: ✓
# - Require status checks: ✓
# - Include administrators: ✓
```

### 2. GitHub Secrets

Add these secrets in your repository settings:

```
AWS_ACCESS_KEY_ID          # Your AWS access key
AWS_SECRET_ACCESS_KEY      # Your AWS secret key
GITHUB_TOKEN              # Automatically provided
```

### 3. AWS Setup

#### Create Staging Environment
```bash
# Tag your staging instance
aws ec2 create-tags \
  --resources i-02962210c91a39e4d \
  --tags Key=Name,Value=InstaRepay-Staging \
  --region us-east-1
```

#### Create Production Environment
```bash
# Create production instance (similar to staging)
./create-ec2.sh
# Tag the new instance as InstaRepay-Prod
```

### 4. Environments

Create environments in GitHub (Settings > Environments):

#### Staging Environment
- Name: `staging`
- Add environment secrets if needed

#### Production Environment
- Name: `production`
- Add environment secrets if needed
- Enable environment protection rules

## Deployment Flow

### Automatic Deployments
- **Push to `dev`**: Deploys to staging
- **Push to `main`**: Deploys to production

### Manual Deployments
```bash
# Deploy to staging
./scripts/deploy-ci.sh staging

# Deploy to production
./scripts/deploy-ci.sh production
```

## Workflows

### 1. `deploy.yml`
- Runs tests on multiple Node.js versions
- Builds and pushes Docker images
- Deploys to appropriate environment based on branch

### 2. `docker-publish.yml`
- Builds separate frontend and backend images
- Publishes to GitHub Container Registry

## Environment Variables

Create `.env.staging` and `.env.production` files:

```bash
# Database
DATABASE_URL=postgresql://...

# JWT
JWT_SECRET=your-secret-key

# Stripe
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...

# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password

# AWS S3
AWS_S3_BUCKET=your-bucket-name
AWS_REGION=us-east-1
```

## Monitoring

After deployment, check:
- Application health: `http://your-ip/health`
- Logs: `docker-compose -f docker-compose.prod.yml logs -f`
- Services: `docker-compose -f docker-compose.prod.yml ps`

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Check if instance is running
   - Verify SSH key permissions (`chmod 400 aws.pem`)
   - Ensure security group allows SSH (port 22)

2. **Docker Build Failed**
   - Check GitHub Actions logs
   - Verify Dockerfile syntax
   - Check for missing dependencies

3. **Deployment Timeout**
   - Increase timeout in workflow
   - Check instance resources (CPU/memory)
   - Verify Docker Compose configuration

### Rollback

To rollback a deployment:
```bash
# SSH to instance
ssh -i aws.pem ubuntu@your-instance-ip

# Rollback containers
cd /opt/instarepay
docker-compose -f docker-compose.prod.yml down
docker-compose -f docker-compose.prod.yml pull
docker-compose -f docker-compose.prod.yml up -d
```

## Security Best Practices

- Use environment-specific secrets
- Enable branch protection rules
- Require code reviews for production
- Regularly rotate AWS credentials
- Monitor deployment logs
- Use least-privilege IAM roles
