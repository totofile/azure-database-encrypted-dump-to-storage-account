# Azure SQL Database Encrypted Backup - Client Version

This guide explains how to use the client-side scripts to export, encrypt, and store Azure SQL databases while running the script from your local workstation.

## Overview

The main client-side script (`encrypt-dump.ps1`) provides a comprehensive solution that:
1. Creates Azure Key Vault and long-lasting certificates (if they don't exist)
2. Connects to Azure SQL Database using Microsoft Entra ID authentication
3. Exports the database to a local BACPAC file
4. Encrypts the BACPAC using the Key Vault certificate
5. Uploads the encrypted file to Azure Blob Storage
6. Cleans up temporary files

The repository also includes separate scripts for testing individual components:
- `create-akv-cert.ps1` - For testing certificate creation independently
- `connect-sql-paas.ps1` - For testing SQL connectivity independently

## Prerequisites

- PowerShell 5.1 or later
- Azure PowerShell modules:
  - Az.Accounts
  - Az.KeyVault
  - Az.Storage
  - Az.Sql
  - SqlServer
- Permissions:
  - Contributor access to the Azure SQL Database
  - Permissions to create/access certificates in Key Vault
  - Storage Blob Data Contributor on the Storage Account

## Using the Main Script

Run the main script to perform the complete process - from key-vault creation to encrypted backup:

```powershell
# Edit variables in encrypt-dump.ps1 or pass them as parameters
.\encrypt-dump.ps1
```

The script will:
1. Connect to Azure using your credentials
2. Create or use an existing Key Vault and certificate
3. Export the database to a local BACPAC file
4. Encrypt the BACPAC using the Key Vault certificate
5. Upload the encrypted file to Azure Blob Storage
6. Clean up temporary files

## Optional Individual Component Testing

### Testing Certificate Creation

If you want to test just the certificate creation process:

```powershell
# Edit variables in create-akv-cert.ps1 or pass them as parameters
.\create-akv-cert.ps1
```

### Testing SQL Connectivity 

To verify Azure SQL Database connectivity independently:

```powershell
# Edit the variables in connect-sql-paas.ps1 or pass them as parameters
.\connect-sql-paas.ps1
```

## Script Parameters

The main script (`encrypt-dump.ps1`) accepts the following parameters:

| Parameter | Description |
|-----------|-------------|
| SubscriptionId | Your Azure subscription ID |
| ResourceGroup | Resource group where your Key Vault will be created or exists |
| Location | Azure region (westeurope, eastus...) |
| KeyVaultName | Name for your Azure Key Vault |
| DbName | Database name used for certificate naming |
| CertificateName | Certificate name in Key Vault (default: "cert-$DbName") |
| SqlServerName | Azure SQL Server FQDN (yourserver.database.windows.net) |
| AzureSqlDatabase | Database to export |
| StorageAccountName | Storage account for storing backups |
| StorageAccountRG | Resource group for the storage account |
| ContainerName | Blob container for backups |

## Security Considerations

- The script uses Microsoft Entra ID authentication for Azure SQL Database access
- The database backup is encrypted with AES-256 using a key protected by the Key Vault certificate
- The encryption process uses a hybrid approach: RSA for key protection and AES for data encryption
- Only users with access to the Key Vault certificate can decrypt the backup
- Temporary files (including the certificate) are securely deleted after processing

## Decrypting Backups

To decrypt the backup files, refer to the [Decryption Instructions](../Decryption/README_DECRYPT.md).

## Troubleshooting

### Authentication Issues

If you encounter authentication issues:

1. Ensure you're logged into the correct Azure account:
   ```powershell
   Connect-AzAccount -Subscription "your-subscription-id"
   ```

2. Verify your account has the necessary permissions on all resources.

### Key Vault or Certificate Issues

The script attempts to create the Key Vault and certificate if they don't exist, but may fail if:

1. You don't have permissions to create resources in the specified resource group
2. The Key Vault name is already taken globally (they must be globally unique)
3. You don't have permissions to create or access certificates

Verify with:
```powershell
Get-AzKeyVault -VaultName "your-keyvault"
Get-AzKeyVaultCertificate -VaultName "your-keyvault" -Name "your-certificate"
```

### Export Failures

If the database export fails:

1. Check if your IP address is allowed in the SQL Server firewall
2. Verify you have permissions to export the database
3. Check if SqlPackage.exe is available (the script attempts to find or download it)
4. Check SQL Server logs for more specific error messages
