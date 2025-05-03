# Decryption Instructions for Azure SQL Database Backups

This document provides instructions for decrypting encrypted BACPAC files that were created using the Azure SQL Database Encrypted Backup Solution.

## Overview

The provided `Decrypt-BacpacFile.ps1` script automates the decryption process, which involves:
1. Connecting to Azure and accessing the certificate in Azure Key Vault
2. Reading the encrypted file's header to identify the Key Vault and certificate used
3. Using the certificate to decrypt the AES key embedded in the file
4. Using the AES key to decrypt the BACPAC file contents
5. Saving the decrypted BACPAC file to the specified location

## Prerequisites

- PowerShell 5.1 or higher
- Azure PowerShell modules:
  - Az.Accounts
  - Az.KeyVault
- Access permissions to the Azure Key Vault and certificate used for encryption
- The encrypted BACPAC file (.bacpac.encrypted)

## Using the Decryption Script

### Script Parameters

| Parameter | Description | Required | Example |
|-----------|-------------|----------|---------|
| SubscriptionId | Your Azure subscription ID | Yes | "00000000-0000-0000-0000-000000000000" |
| TenantId | Your Azure tenant ID | Yes | "00000000-0000-0000-0000-000000000000" |
| InputFile | Path to the encrypted file | Yes | "C:\path\to\your-database-file-name.bacpac.encrypted" |
| OutputFile | Path where decrypted BACPAC will be saved | Yes | "C:\path\to\your-database-name.bacpac" |
| Debug | Enable verbose logging (optional) | No | $false |

### Example Usage

```powershell
.\Decrypt-BacpacFile.ps1 -SubscriptionId "your-subscription-id" `
                         -TenantId "your-tenant-id" `
                         -InputFile "C:\path\to\encrypted.bacpac.encrypted" `
                         -OutputFile "C:\path\to\decrypted.bacpac"
```

## Decryption Process

When you run the script, it performs the following operations:

1. **Authentication**: Connects to Azure using the specified subscription and tenant
2. **File Analysis**: Reads the encrypted file header to extract:
   - The certificate name used for encryption
   - The Key Vault where the certificate is stored
   - The encrypted AES key and initialization vector
3. **Key Decryption**: Decrypts the AES key using the certificate from Key Vault
4. **Content Decryption**: Uses the decrypted AES key to decrypt the file contents
5. **Output**: Saves the decrypted BACPAC file to the specified location

The script automatically handles all aspects of the decryption process and has multiple fallback methods to ensure successful decryption.

## Importing the Decrypted BACPAC

After decryption, you can import the BACPAC file into any compatible SQL Server environment.

### Using SQL Server Management Studio (SSMS)

1. Open SQL Server Management Studio and connect to your target server
2. Right-click on the Databases folder
3. Select "Import Data-tier Application..."
4. Follow the wizard, selecting your decrypted BACPAC file
5. Complete the import process

### Using SqlPackage.exe

SqlPackage.exe provides command-line options for importing the BACPAC:

```powershell
& "C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe" `
  /Action:Import `
  /SourceFile:"C:\path\to\decrypted.bacpac" `
  /TargetServerName:"YourSQLServer" `
  /TargetDatabaseName:"YourDatabaseName" `
  /TargetUser:"YourUsername" `
  /TargetPassword:"YourPassword"
```

## Security Considerations

- The decryption script temporarily accesses the certificate but doesn't store it locally
- If certificate export is required (fallback method), the certificate is securely deleted after use
- Store decrypted BACPAC files securely as they contain unencrypted database content
- Run the decryption process on a secure workstation with appropriate access controls

## Troubleshooting

### Authentication Issues

- Ensure you have the correct Subscription ID and Tenant ID
- Verify you're authorized to access the Key Vault and certificate
- Try running `Connect-AzAccount` manually before running the script

### Decryption Failures

- Verify the encrypted file hasn't been corrupted or modified
- Ensure you have permissions to the certificate in Key Vault
- Check if the script outputs any specific error messages

### File Format Issues

- If you see "Invalid file format" errors, the file may not be in the expected format
- Ensure the file was encrypted using the Azure SQL Database Encrypted Backup Solution
