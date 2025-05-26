# Azure Automation Runbook Scripts

PowerShell scripts for automated, secure backups of Azure SQL Managed Instance and Azure SQL Database, designed to run as Azure Automation runbooks.

## Scripts & Functionality

1.  **`SQLMI-InvokeSqlCmd-Secure-Backup-Runbook.ps1` (Recommended for SQL MI)**:
    *   Uses Managed Identity authentication to securely connect to SQL Managed Instance.
    *   Executes native backup using `BACKUP DATABASE TO URL` via `Invoke-Sqlcmd`.
    *   Downloads, encrypts (AES-256), and uploads the `.bak.encrypted` file to Azure Blob Storage.
    *   **Note**: Requires `SqlServer` PowerShell module in Azure Automation.

2.  **`encrypt-dump-NewAzSqlExport-method.PS1` (For Azure SQL Database)**:
    *   Uses Azure API to export Azure SQL Database to BACPAC.
    *   Encrypts and uploads the `.bacpac.encrypted` file to Azure Blob Storage.

## SQL Managed Instance Advantages

- **Secure Authentication**: Azure Automation Managed Identity
- **Native Backup**: Standard T-SQL `BACKUP DATABASE` command
- **Optimal Performance**: Built-in SQL Server compression
- **Native Format**: High-performance .bak format
- **Simplicity**: Single T-SQL command

## Installation

### 1. Prerequisites
- Azure Automation Account with system-assigned managed identity
- SQL Managed Instance
- Azure Key Vault with certificate
- Azure Storage Account

### 2. SQL Configuration (Required)
Connect to your SQL Managed Instance and execute:

```sql
-- Replace [automation_account_name] with your managed identity name
-- (This name appears in the runbook logs)
CREATE USER [automation_account_name] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [automation_account_name];
```

**Note**: The managed identity name appears in the logs during connection testing.

### 3. Azure Permissions
Your managed identity needs:
- **Storage Blob Data Contributor** on the Storage Account
- **Key Vault Crypto User** on the Key Vault
- **Reader** on the Resource Group

### 4. Automation-Account Import Module
1. Azure Portal → Automation Account
2. Automation Account → Import a runbook module named *SqlServer*
3. Select `SQL-Managed-Instance-Secure-Backup-Runbook.ps1`→ copy/paste script 
4. Configure parameters

## Configuration

### Runbook Parameters
```powershell
$SubscriptionId = "your-subscription-id"
$ResourceGroup = "your-resource-group"
$KeyVaultName = "your-key-vault"
$SqlServerName = "your-sqlmi-instance"        # Without .database.windows.net
$AzureSqlDatabase = "your-database"
$StorageAccountName = "your-storage-account"
$ContainerName = "backup"
$CertificateName = "your-certificate-name"
```

## Operation

### 1. Azure Connection
- Azure AD authentication
- Subscription selection
- Permission validation

### 2. Database Backup
- Native backup via T-SQL
- File integrity validation
- Compression enabled

### 3. Encryption
- Key Vault certificate retrieval
- AES-256 + RSA encryption
- Creation of `.encrypted` file

### 4. Secure Upload
- Upload to Azure Blob Storage
- SAS URL generation for download
- Temporary file cleanup

## Performance

### Typical Times
- **Small DB** (< 10 GB): 5-15 minutes
- **Medium DB** (10-100 GB): 15-45 minutes
- **Large DB** (> 100 GB): 45+ minutes

### Optimization
- Uses SQL Server native compression
- Parallel backup operations where possible
- Efficient blob storage upload

## Support

For issues:
1. Check Azure Automation logs
2. Verify managed identity permissions
3. Test SQL connectivity
4. Review detailed PowerShell logs

## Security

- **Strong Authentication**: Azure AD only
- **End-to-End Encryption**: No clear-text data
- **Automatic Rotation**: Key Vault certificates
- **Complete Audit**: Azure Activity logs 
