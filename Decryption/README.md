# Backup Decryption Tool (`decrypt.ps1`)

This script decrypts `.bak.encrypted` or `.bacpac.encrypted` files previously encrypted by this solution's backup scripts.

## Functionality

Uses an Azure Key Vault certificate to:
1. Decrypt the AES key embedded in the encrypted file.
2. Decrypt the file content using the AES key (AES-256).
3. Save the decrypted file (e.g., `database.bak` or `database.bacpac`).

Optionally, it can attempt to auto-restore `.bak` files to a specified SQL Server.

## Prerequisites

- PowerShell 5.1+
- Azure PowerShell Modules: `Az.Accounts`, `Az.KeyVault`.
- Access to the Azure Key Vault and the specific certificate used for encryption.
- The `.encrypted` backup file.

## Basic Usage

```powershell
# Ensure you are connected to Azure: Connect-AzAccount

.\decrypt.ps1 -EncryptedFile "path\to\your\database.bak.encrypted" `
              -KeyVaultName "your-key-vault-name" `
              -CertificateName "your-certificate-name"

# For auto-restore (primarily for .bak files):
# .\decrypt.ps1 -EncryptedFile "..." -KeyVaultName "..." -CertificateName "..." -SqlServer "YourSQLInstance" -DatabaseName "TargetDB" -AutoRestore
```

Refer to script comments for more parameters (`-OutputPath`, `-OverwriteExisting`, etc.).

## Features

- **Secure Decryption**: Azure Key Vault certificate-based
- **Multi-format Support**: Compatible with .bak (SQL MI) and .bacpac (Azure SQL DB)
- **Portability**: Restore to any SQL Server instance
- **Data Integrity**: Automatic backup validation
- **Flexibility**: Local or cloud-based decryption

## Authentication Methods

### Interactive Authentication
```powershell
# Browser-based login (recommended)
Connect-AzAccount
.\decrypt.ps1 -EncryptedFile "file.encrypted" -KeyVaultName "kv"
```

### Service Principal
```powershell
# Automated authentication (ensure Service Principal has necessary Key Vault permissions)
$ClientId = "your-sp-application-id"
$ClientSecret = "your-sp-client-secret"
$TenantId = "your-azure-tenant-id"

$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential = New-Object PSCredential($ClientId, $SecureSecret)
Connect-AzAccount -ServicePrincipal -Credential $Credential -TenantId $TenantId

.\decrypt.ps1 -EncryptedFile "path\to\your\file.encrypted" -KeyVaultName "your-key-vault-name"
```

## Decryption and Restore Process

### 1. Download Encrypted File (Manual Step)
If your encrypted backup file is in Azure Blob Storage, download it first.
```powershell
# Example: Download from Azure Blob Storage
$StorageAccountName = "yourstorageaccount"
$ContainerName = "backupcontainer"
$BlobName = "database.bak.encrypted"
$DestinationPath = "C:\Temp\$BlobName"

$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount # or use -StorageAccountKey
Get-AzStorageBlobContent -Container $ContainerName `
                         -Blob $BlobName `
                         -Destination $DestinationPath `
                         -Context $StorageContext
```

### 2. Decryption using `decrypt.ps1`
The `decrypt.ps1` script performs the following actions:
- Connects to Azure Key Vault to retrieve the specified certificate.
- Uses the certificate's private key to decrypt the AES key embedded in the encrypted file's header.
- Uses the decrypted AES key to decrypt the actual file content (AES-256).
- Performs an integrity validation (e.g., checks if the decrypted file has a valid .bak or .bacpac structure if possible, verifies size).
- Saves the decrypted file (e.g., `database.bak` or `database.bacpac`) to the specified output path.

### 3. Database Restore (Manual or Automated)
Once the file is decrypted, restore it using standard SQL Server methods:
```powershell
# For .bak files (typically from SQL Managed Instance backups)
RESTORE DATABASE [YourTargetDatabaseName] 
FROM DISK = 'C:\Temp\database.bak' # Path to decrypted .bak file
WITH REPLACE, STATS = 10;

# For .bacpac files (typically from Azure SQL Database exports)
# Ensure SqlPackage.exe is in your PATH or provide the full path
# e.g., & "C:\Program Files\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe" ...
SqlPackage.exe /Action:Import /SourceFile:"C:\Temp\database.bacpac" /TargetServerName:"your-sql-server-instance" /TargetDatabaseName:"YourTargetDatabaseName" # Add other params as needed (e.g., auth)
```
If using the `-AutoRestore` parameter with `decrypt.ps1`, the script attempts this step automatically.

## Script Parameters

### Required Parameters
```powershell
-EncryptedFile      # Path to encrypted file
-KeyVaultName       # Key Vault containing the certificate
-CertificateName    # Name of the certificate in Key Vault used for decryption
```

### Optional Parameters
```powershell
-OutputPath         # Output directory for the decrypted file (default: same directory as the input file)
-SqlServer          # SQL Server instance name for automatic restore (e.g., "localhost\SQLEXPRESS")
-DatabaseName       # Target database name for automatic restore
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
| `File corrupted` | Data integrity issue (e.g., incomplete download) | Re-download from source, verify file size/checksum if available |
| `Access denied` | Insufficient permissions to Key Vault, Storage, or SQL Server | Check Azure roles & SQL permissions |

### Integrity Validation Details
The script performs basic checks. For .bak files, a more thorough validation occurs if a restore is attempted. For .bacpac, the structure is more complex to validate pre-import without specialized tools.
Always verify the restored database manually after the process.

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