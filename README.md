# Azure SQL Database Encrypted Backup Solution

A comprehensive solution for securely exporting, encrypting, and archiving Azure SQL Database backups on Azure storage account using Azure Key Vault.

## Overview

This repository provides tools for secure database archiving with end-to-end encryption. The solution addresses security concerns when storing sensitive database backups by ensuring that data remains encrypted at rest and can only be decrypted by authorized users with access to the encryption certificate.

The workflow involves:
1. Exporting an Azure SQL Database to BACPAC format
2. Encrypting the BACPAC file using a certificate from Azure Key Vault
3. Storing the encrypted backup in Azure Blob Storage
4. Providing secure decryption capabilities when needed

## Repository Structure

The repository is organized into three main components:

### 1. Client-Side Scripts (`from-client-dump-encrypt-db/`)
- `encrypt-dump.ps1` - Main script for exporting and encrypting databases from a local workstation
- `create-akv-cert.ps1` - Creates long-term certificates in Azure Key Vault this script is for testing and is also into the main that do all the job end-to-end
- `connect-sql-paas.ps1` - Tests connectivity to Azure SQL Database with Microsoft Entra ID
- `README_CLIENT.md` - Detailed instructions for client-side operations

### 2. Azure Automation Scripts (`from-azure-runbook-dump-encrypt-db/`)
- `runbook-encrypt-dump.ps1` - Azure Runbook script for automated/scheduled backups
- `README_RUNBOOK.md` - Instructions for setting up and using the automation solution

### 3. Decryption Tools (`Decryption/`)
- `Decrypt-BacpacFile.ps1` - Script for decrypting the backup files from both client and runbook solutions
- `README_DECRYPT.md` - Instructions for the decryption process

## Key Features

- **Strong Encryption**: Implements AES-256 encryption with keys protected by Azure Key Vault certificates
- **Hybrid Encryption Model**: Uses asymmetric encryption (RSA) for the AES key and symmetric encryption for the data
- **Microsoft Entra ID Integration**: Uses Microsoft Entra ID authentication for secure access to Azure resources
- **Flexible Deployment Options**: Run as client-side scripts or as an Azure Automation runbook
- **Platform Independence**: Encrypted backups can be decrypted and restored on any Azure SQL Server

## Security Architecture

- **Key Management**: All encryption keys are secured in Azure Key Vault
- **No Shared Secrets**: The encryption certificate is never stored permanently outside of Key Vault
- **Defense in Depth**: Uses a dual-layer encryption approach (RSA + AES)
- **Access Control**: Only users with appropriate Key Vault permissions can access the encryption certificates

## Getting Started

Choose the appropriate approach based on your operational requirements:

1. [Client-Side Operations](from-client-dump-encrypt-db/README_CLIENT.md) - Run the scripts from a workstation or server
2. [Automated Operations](from-azure-runbook-dump-encrypt-db/README_RUNBOOK.md) - Set up scheduled backups using Azure Automation
3. [Backup Decryption](Decryption/README_DECRYPT.md) - Decrypt backups when needed

## Prerequisites

- PowerShell 5.1 or later
- Azure PowerShell modules:
  - Az.Accounts
  - Az.KeyVault
  - Az.Storage
  - Az.Sql
  - SqlServer
- Appropriate permissions on Azure resources:
  - Contributor access to Azure SQL Database
  - Access to create/manage certificates in Azure Key Vault
  - Storage Blob Data Contributor on the target Storage Account

## Compliance and Best Practices

This solution follows security best practices for:
- Secure data export
- Key management
- Encryption at rest
- Principle of least privilege
- Separation of duties

## License

This project is licensed under the MIT License - see the LICENSE file for details.
