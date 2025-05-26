# Azure SQL Backup Decryption Tool

Decryption tools for encrypted backups created by Azure SQL Backup Solution.

## Overview

This module provides tools to decrypt backup files encrypted with Azure Key Vault certificates and restore them to any compatible SQL Server.

## Features

- **Secure Decryption**: Azure Key Vault certificate-based
- **Multi-format Support**: Compatible with .bak (SQL MI) and .bacpac (Azure SQL DB)
- **Portability**: Restore to any SQL Server instance
- **Data Integrity**: Automatic backup validation
- **Flexibility**: Local or cloud-based decryption

## Prerequisites

- PowerShell 5.1 or higher
- Azure PowerShell modules:
  - Az.Accounts
  - Az.KeyVault
- Access to the Azure Key Vault and encryption certificate
- Encrypted backup file (.bak.encrypted or .bacpac.encrypted)

## Quick Start

### Basic Decryption
```powershell
# Decrypt a backup file
.\decrypt.ps1 -EncryptedFile "database-20250526_123456.bak.encrypted" `
              -KeyVaultName "your-key-vault" `
              -CertificateName "cert-encryption"
```

### With Automatic Restore
```powershell
# Decrypt and restore in one step
.\decrypt.ps1 -EncryptedFile "database.bak.encrypted" `
              -KeyVaultName "your-key-vault" `
              -CertificateName "cert-encryption" `
              -SqlServer "your-sql-server" `
              -DatabaseName "database-restored" `
              -AutoRestore
```

## Authentication Methods

### Interactive Authentication
```powershell
# Browser-based login (recommended)
Connect-AzAccount
.\decrypt.ps1 -EncryptedFile "file.encrypted" -KeyVaultName "kv"
```

### Service Principal
```powershell
# Automated authentication
$ClientId = "app-id"
$ClientSecret = "secret"
$TenantId = "tenant-id"

$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential = New-Object PSCredential($ClientId, $SecureSecret)
Connect-AzAccount -ServicePrincipal -Credential $Credential -TenantId $TenantId

.\decrypt.ps1 -EncryptedFile "file.encrypted" -KeyVaultName "kv"
```

## Decryption Workflow

### 1. Download Encrypted File
```powershell
# Download from Azure Blob Storage
$StorageContext = New-AzStorageContext -StorageAccountName "storage" -UseConnectedAccount
Get-AzStorageBlobContent -Container "backup" `
                         -Blob "database.bak.encrypted" `
                         -Destination "C:\Temp\" `
                         -Context $StorageContext
```

### 2. Decryption Process
The script automatically handles:
- Key Vault certificate retrieval
- RSA decryption of AES key
- AES-256 file decryption
- Integrity validation

### 3. Database Restore
```powershell
# For .bak files (SQL Managed Instance)
RESTORE DATABASE [DatabaseName] 
FROM DISK = 'C:\Temp\database.bak'
WITH REPLACE, STATS = 10;

# For .bacpac files (Azure SQL Database)
SqlPackage.exe /Action:Import /SourceFile:"database.bacpac" /TargetServerName:"server" /TargetDatabaseName:"database"
```

## Script Parameters

### Required Parameters
```powershell
-EncryptedFile      # Path to encrypted file
-KeyVaultName       # Key Vault containing the certificate
-CertificateName    # Decryption certificate name
```

### Optional Parameters
```powershell
-OutputPath         # Output directory (default: same as input)
-SqlServer          # SQL Server for automatic restore
-DatabaseName       # Target database name
-AutoRestore        # Enable automatic restore
-OverwriteExisting  # Overwrite existing files
-KeepDecrypted      # Retain decrypted file after restore
```

## Security

### Required Permissions
- **Key Vault Crypto User**: Certificate access
- **Storage Blob Data Reader**: Encrypted file download
- **sysadmin** or **dbcreator**: SQL Server restore

### Best Practices
- Use managed identities when possible
- Limit decryption certificate access
- Clean up temporary files
- Audit all backup access

## Troubleshooting

### Common Issues

| Error | Cause | Solution |
|--------|-------|----------|
| `Certificate not found` | Missing/deleted certificate | Verify Key Vault certificate |
| `Decryption failed` | Wrong certificate | Use correct encryption certificate |
| `File corrupted` | Data integrity issue | Re-download from blob |
| `Access denied` | Insufficient permissions | Check Azure roles |

### Integrity Validation
The script automatically verifies:
- Decrypted file size
- Checksum (if available)
- File format (.bak/.bacpac)

### Debug Mode
```powershell
# Enable detailed logging
.\decrypt.ps1 -EncryptedFile "file.encrypted" -KeyVaultName "kv" -Verbose
```

## Performance

### Decryption Times
- **Small DB** (< 1 GB): 1-2 minutes
- **Medium DB** (1-10 GB): 3-10 minutes
- **Large DB** (10+ GB): 10+ minutes

### Optimization Tips
- Use SSD for temporary files
- Ensure sufficient disk space (2x file size)
- Run decryption on powerful machine

## Support

For issues:
1. Check Key Vault permissions with `Get-AzKeyVaultAccessPolicy`
2. Test Azure connectivity with `Test-AzKeyVaultConnection`
3. Validate encrypted file integrity
4. Review detailed logs with `-Verbose`
5. Verify available disk space 