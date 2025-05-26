# Azure SQL Secure Backup & Encryption

Automated solution for creating encrypted backups of Azure SQL databases (.bak for MI, .bacpac for Azure SQL DB) using Azure Key Vault and storing them in Azure Blob Storage. Includes client scripts for local operations and decryption tools.

## Core Functionality

- **Azure Automation Runbooks**: For server-side, scheduled backups.
    - SQL Managed Instance: Uses `Invoke-SqlCmd` `BACKUP DATABASE TO URL` (native `.bak`).
    - Azure SQL Database: Uses `New-AzSqlDatabaseExport` (`.bacpac`).
- **Client Scripts**: For local/manual BACPAC export, encryption, and upload.
- **Decryption Script**: Decrypts both `.bak.encrypted` and `.bacpac.encrypted` files.

## Prerequisites (General)

- Azure Subscription & appropriate permissions.
- Azure Key Vault with a certificate for encryption/decryption.
- Azure Storage Account for storing backups.
- PowerShell 5.1+ with Azure modules (Az.Accounts, Az.KeyVault, Az.Storage, Az.Sql, SqlServer) for client scripts and runbook setup.

## Repository Structure Overview

```
.
├── README.md                                         # This overview
├── encrypted-azure-sql-&-sqlmi-backup-to-blob-storage/
│   ├── from-azure-runbook-dump-encrypt-db/         # Azure Automation runbook scripts & guide
│   └── from-client-scripts/                        # Client-side scripts & guide
└── Decryption/                                       # Decryption tool & guide
```

See README files in subdirectories for specific script details and prerequisites.

## Security

- Employs Managed Identities for Azure Automation.
- Uses Azure Key Vault for secure certificate management.
- AES-256 encryption for backup files.

## License

MIT License. Refer to the LICENSE file.
