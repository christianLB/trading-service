# Secrets Directory

This directory contains sensitive configuration files that should NEVER be committed to version control.

## Required Files for Production

### 1. API Token
Create `api_token.txt` with your secure bearer token:
```bash
openssl rand -hex 32 > api_token.txt
```

### 2. Database Password
Create `db_password.txt` with a strong password:
```bash
openssl rand -base64 32 > db_password.txt
```

### 3. Webhook Secret
Create `webhook_secret.txt` for HMAC signing:
```bash
openssl rand -hex 32 > webhook_secret.txt
```

### 4. Exchange API Credentials (when ready)
Create `exchange_credentials.json`:
```json
{
  "binance": {
    "api_key": "your-api-key",
    "api_secret": "your-api-secret"
  },
  "coinbase": {
    "api_key": "your-api-key",
    "api_secret": "your-api-secret"
  }
}
```

## Security Best Practices

1. **Never commit secrets** - This directory is gitignored
2. **Use strong passwords** - Minimum 32 characters, randomly generated
3. **Rotate regularly** - Change secrets every 90 days
4. **Backup securely** - Store encrypted copies in a password manager
5. **Limit access** - Only production deployment should access these files

## Deployment Usage

The production deployment scripts will look for these files when:
- Setting up initial environment
- Updating configuration
- Rotating credentials

## File Permissions

On the NAS, ensure proper permissions:
```bash
chmod 600 /volume1/docker/trading-service/secrets/*
chown $USER:users /volume1/docker/trading-service/secrets/*
```