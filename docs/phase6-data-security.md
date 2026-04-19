# Phase 6: Data Security Runbook

This runbook covers the three Phase 6 deliverables:

1. HTTPS/TLS for application traffic
2. Secrets stored in AWS Secrets Manager
3. Encryption-at-rest verification (EKS secrets, EBS, and optional RDS)

## 1) Apply Infrastructure Changes

The Terraform changes in this repository add:

- A dedicated Secrets Manager secret container for backend configuration
- A least-privilege IRSA policy scoped to that secret

Run:

```bash
cd terraform
terraform init
terraform apply
```

Capture evidence:

- `terraform output app_backend_secret_name`
- `terraform output app_backend_secret_arn`

## 2) Store Backend Secrets in AWS Secrets Manager

Create or update secret values (example payload):

```bash
aws secretsmanager put-secret-value \
  --region us-west-2 \
  --secret-id fintech-secure-dev-backend \
  --secret-string '{
    "SECRET_KEY":"replace-me-strong-secret",
    "JWT_SECRET_KEY":"replace-me-strong-jwt-secret",
    "DATABASE_URL":"postgresql://fintech_user:fintech_password@db:5432/fintech_db",
    "CORS_ORIGINS":"https://fintech.example.com"
  }'
```

Capture evidence:

- Secrets Manager secret details page showing latest version
- Redacted screenshot of key names (not values)

## 3) Wire Backend Pod to IRSA + Secret Name

Apply the service account manifest:

```bash
kubectl apply -f kubernetes/secrets/app-backend-serviceaccount.yaml
```

Before applying, replace role ARN placeholder with:

```bash
terraform output app_workload_role_arn
```

In backend deployment, set:

- `serviceAccountName: app-backend`
- env var: `APP_SECRETS_NAME=fintech-secure-dev-backend`
- optional env var: `AWS_REGION=us-west-2`

The backend config now supports Secrets Manager lookup with env fallback.

## 4) Configure HTTPS (ACM + Ingress)

1. Request/import certificate in ACM (region: `us-west-2`)
2. Validate DNS
3. Update `kubernetes/ingress/app-ingress-acm.yaml`:
   - certificate ARN
   - host name
4. Apply ingress:

```bash
kubectl apply -f kubernetes/ingress/app-ingress-acm.yaml
```

Capture evidence:

- ACM certificate `Issued`
- Ingress manifest with HTTPS annotations
- Browser/network screenshot proving HTTPS access

## 4.1) If You Do Not Own a Custom Domain Yet (Vercel + EKS Path)

If you only have a Vercel-managed hostname (for example `*.vercel.app`) and cannot add custom DNS validation records for ACM:

1. Keep frontend hosted on Vercel.
2. Expose backend through EKS/ALB endpoint.
3. Set frontend `VITE_API_URL` to the ALB endpoint.
4. Set backend `CORS_ORIGINS` to your Vercel domain in Secrets Manager.
5. Document TLS manifest readiness and note that ACM issuance is pending custom DNS ownership.

Example values:

- `VITE_API_URL=http://<alb-dns-name>/api`
- `CORS_ORIGINS=https://secure-eks-deployment.vercel.app`

## 5) Verify Encryption at Rest

### EKS secrets encryption (KMS)

```bash
aws eks describe-cluster \
  --region us-west-2 \
  --name fintech-secure-dev \
  --query 'cluster.encryptionConfig'
```

### EBS encryption on worker node volume

```bash
aws ec2 describe-instances \
  --region us-west-2 \
  --filters "Name=tag:eks:cluster-name,Values=fintech-secure-dev" \
  --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId' \
  --output text
```

Then for each volume id:

```bash
aws ec2 describe-volumes \
  --region us-west-2 \
  --volume-ids <VOLUME_ID> \
  --query 'Volumes[].{VolumeId:VolumeId,Encrypted:Encrypted,KmsKeyId:KmsKeyId}'
```

### RDS encryption (if using RDS)

```bash
aws rds describe-db-instances \
  --region us-west-2 \
  --query 'DBInstances[].{DBInstanceIdentifier:DBInstanceIdentifier,StorageEncrypted:StorageEncrypted,KmsKeyId:KmsKeyId}'
```

## 6) Submission Evidence Checklist

- ACM certificate status (`Issued`)
- Ingress HTTPS annotations (`ssl-redirect`, certificate ARN)
- Secrets Manager secret exists with current version
- IRSA service account annotation present
- EKS encryption config output
- EBS volume `Encrypted=true`
- RDS `StorageEncrypted=true` (if applicable)

### Recommended Evidence if ACM Cannot Be Issued Yet

- Secrets Manager secret with backend keys configured
- Backend IRSA role and service account mapping
- EKS secrets encryption config (KMS)
- EBS encryption evidence (`Encrypted=true`)
- Ingress manifest showing TLS annotations and ACM integration design
- Short note explaining DNS ownership limitation for final ACM validation
