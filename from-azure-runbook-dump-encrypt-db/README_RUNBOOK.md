# Azure SQL Database Encrypted Backup Runbook Guide

This guide explains how to configure, run, and use the PowerShell runbook to automatically export and encrypt Azure SQL Databases, and how to decrypt the backups for use on any SQL Server.

## Table of Contents

- [System Overview](#system-overview)
- [Prerequisites](#prerequisites)
- [Runbook Configuration](#runbook-configuration)
- [Runbook Execution](#runbook-execution)
- [Backup Retrieval and Decryption](#backup-retrieval-and-decryption)
- [Troubleshooting](#troubleshooting)

## System Overview

This solution automates the export of Azure SQL Databases to BACPAC format, encrypts them with a certificate stored in Azure Key Vault, and saves the encrypted file to Azure Blob Storage. The automation runs entirely within Azure, eliminating the need for client-side operations.

## Prerequisites

### Azure Resources
- Azure account with necessary permissions
- Azure Automation Account with managed identity
- Azure Key Vault with a certificate for encryption
- Azure SQL Database to back up
- Azure Storage Account with a container for backups

### Permissions
The Automation Account's managed identity must have the following permissions:
- Contributor on Azure SQL Database
- Reader and Data Manager on the storage account
- Certificate and key user on Key Vault

## Runbook Configuration

### 1. Creating the Runbook in Azure Automation

1. In the Azure portal, go to your Automation Account
2. Select **Runbooks** > **+ Create a runbook**
3. Enter a name (e.g., `Export-EncryptDB`)
4. Select **PowerShell** as the runbook type
5. Click **Create**
6. Copy the content of the `runbook-encrypt-dump.PS1` file into the editor
7. Click **Publish**

### 2. Configuring the Managed Identity

1. In your Automation Account, go to **Identity**
2. Enable the system-assigned managed identity
3. Note the Object ID that will be used for role assignments

### 3. Runbook Parameters

Modify the runbook's default parameters to suit your environment:

| Parameter | Description |
|-----------|-------------|
| SubscriptionId | Your Azure subscription ID |
| ResourceGroup | Resource group containing the Azure SQL Database |
| KeyVaultName | Name of the Key Vault containing the encryption certificate |
| SqlServerName | SQL server name (without the .database.windows.net suffix) |
| AzureSqlDatabase | Name of the database to export |
| StorageAccountName | Storage account name for storing backups |
| StorageAccountRG | Resource group for the storage account |
| ContainerName | Container name in the storage account |
| CertificateName | Certificate name in the Key Vault |
| AdminLogin | Microsoft Entra ID username (email format) |
| AdminPassword | Microsoft Entra ID account password |

## Runbook Execution

### Manual Execution

1. In the Azure portal, go to your Automation Account
2. Select the runbook you created previously
3. Click **Start**
4. Verify or update the parameters
5. Click **OK** to start execution
6. Wait for the execution to complete and check the output to verify success

### Scheduling Automated Executions

1. In the Azure portal, go to your Automation Account > Runbooks
2. Select your runbook and click **Schedules**
3. Click **+ Add a schedule**
4. Configure a schedule by selecting the desired time and frequency
5. Configure the parameters to use during scheduled execution

## Backup Retrieval and Decryption

To retrieve and decrypt your backups, refer to the [Decryption Instructions](../Decryption/README_DECRYPT.md) for detailed steps.

## Troubleshooting

### Authentication Issues

If the runbook fails with authentication errors:
- Verify the Microsoft Entra ID credentials are correct
- Ensure the managed identity has all required permissions
- Check that the Microsoft Entra ID user is an admin of the SQL server

### Export Failures

If the export operation fails:
- Verify network rules allow access from Automation to SQL and Storage
- Check that the SQL Database exists and is accessible
- Review the runbook output logs for specific error messages

### Encryption Issues

If encryption operations fail:
- Verify Key Vault permissions (the managed identity needs encrypt/decrypt permissions)
- Ensure the certificate exists and is valid
- Check that the certificate name is correctly specified in parameters
