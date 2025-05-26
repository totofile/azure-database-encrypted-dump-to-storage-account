# Azure SQL Secure Backup & Encryption

Secure solution for backing up and encrypting Azure SQL databases using Azure Key Vault and Blob Storage.

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Azure](https://img.shields.io/badge/Azure-Automation-0089D6.svg)](https://azure.microsoft.com/services/automation/)

## Overview

This repository provides PowerShell scripts for creating secure, encrypted backups of Azure SQL databases. The solution uses Azure Key Vault certificates for encryption and stores backups in Azure Blob Storage, with a focus on security and automation.

## Repository Structure

```
.
├── README.md                                             # Main documentation
├── encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/
│   ├── from-azure-runbook-dump-encrypt-db/             # Scripts for Azure Automation runbooks
│   │   ├── SQLMI-InvokeSqlCmd-Secure-Backup-Runbook.ps1  # Primary script for SQL Managed Instance (.bak)
│   │   ├── encrypt-dump-NewAzSqlExport-method.PS1      # Alternative for Azure SQL Database (.bacpac)
│   │   └── README.md                                     # Guide for these runbooks
│   └── from-client-scripts/                            # Utility scripts for local execution
│       ├── connect-sql-paas.ps1                        # SQL connectivity testing script
│       ├── create-akv-cert.ps1                         # Script to create AKV certificate
│       ├── encrypt-dump.PS1                            # Client-side encryption script
│       ├── README.md                                     # Main guide for client scripts
│       └── README_CLIENT.md                              # Additional client script details (consider merging)
└── Decryption/                                           # Tools for decrypting backups
    ├── decrypt.ps1                                     # Main decryption script
    └── README.md                                       # Decryption guide
```

## Features

### SQL Managed Instance (Recommended)
**Script:** `encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/from-azure-runbook-dump-encrypt-db/SQLMI-InvokeSqlCmd-Secure-Backup-Runbook.ps1`

- **Secure Authentication**: Azure Automation Managed Identity
- **Native Backup**: Standard T-SQL `BACKUP DATABASE` command
- **Optimal Performance**: Built-in SQL Server compression
- **Native Format**: High-performance .bak format

### Azure SQL Database
**Script:** `encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/from-azure-runbook-dump-encrypt-db/encrypt-dump-NewAzSqlExport-method.PS1`

- **API-based**: BACPAC export via Azure API (suitable for Azure SQL DB singletons/elastic pools)
- **Complex Authentication**: May require additional setup compared to Managed Identity with SQL MI.

## Quick Start

### Prerequisites
- Azure Automation Account with system-managed identity
- SQL Managed Instance or Azure SQL Database
- Azure Key Vault with certificate
- Azure Storage Account

### SQL Configuration
Connect to your database and execute:

```sql
-- Replace [your_automation_account_name] with the name of your Azure Automation account's Managed Identity
CREATE USER [your_automation_account_name] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [your_automation_account_name];
```

### Deployment Steps
1. Import script into Azure Automation
2. Configure runbook parameters
3. Schedule automated execution

## Security Features

- **Passwordless Authentication**: Azure Managed Identity
- **AES-256 Encryption**: Keys managed by Azure Key Vault
- **Automatic Key Rotation**: Azure Key Vault certificates
- **Least Privilege**: Minimal required permissions

## Solution Comparison

| Criteria | SQL Managed Instance | Azure SQL Database |
|----------|---------------------|-------------------|
| **Performance** | Excellent | Good |
| **Complexity** | Simple | Complex |
| **Format** | .bak (native) | .bacpac (export) |
| **Size** | Compressed | Larger |
| **Speed** | Fast | Slower |

## Usage

### SQL Managed Instance Configuration
```powershell
# Runbook configuration
$SqlServerName = "your-sqlmi-instance"
$AzureSqlDatabase = "your-database"
$StorageAccountName = "your-storage"
$KeyVaultName = "your-keyvault"
```

### Execution Methods
- Manual execution from Azure portal
- Scheduled automation
- Webhook triggers

## Detailed Documentation

- [Azure Automation Runbook Guide](encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/from-azure-runbook-dump-encrypt-db/README.md)
- [Client Scripts Guide](encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/from-client-scripts/README.md)
- [Decryption Guide](Decryption/README.md)

## Troubleshooting

For issues:
1. Check Azure Automation logs
2. Validate managed identity permissions
3. Test SQL connectivity with `Invoke-Sqlcmd`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
