# Azure Automation Runbook Scripts

PowerShell scripts for automated, secure backups of Azure SQL Managed Instance and Azure SQL Database, designed to run as Azure Automation runbooks.

## Scripts & Functionality

1.  **`SQLMI-InvokeSqlCmd-Secure-Backup-Runbook.ps1` (Recommended for SQL MI)**:
    *   Connects to SQL Managed Instance using Managed Identity.
    *   Executes `BACKUP DATABASE ... TO URL` for native `.bak` creation with compression.
    *   Downloads the `.bak` file, encrypts it (AES-256 with Key Vault cert), and re-uploads the `.bak.encrypted` to Azure Blob Storage.
    *   **Note**: The Azure Automation account requires the `SqlServer` PowerShell module to be imported for `Invoke-Sqlcmd` and related cmdlets if not using a Hybrid Worker with the module pre-installed.

2.  **`encrypt-dump-NewAzSqlExport-method.PS1` (For Azure SQL Database PaaS)**:
    *   Connects to Azure SQL Database (PaaS singletons/elastic pools).
    *   Uses `New-AzSqlDatabaseExport` to create a `.bacpac` file directly in Azure Blob Storage.
    *   Downloads the `.bacpac`, encrypts it (AES-256 with Key Vault cert), and re-uploads the `.bacpac.encrypted` to Azure Blob Storage.

## Prerequisites (General for Runbooks)

- Azure Automation Account with a System-Assigned Managed Identity.
- **Managed Identity Permissions**:
    - SQL Server: `db_owner` (or specific backup/connect permissions) on the target database(s). Create user from external provider: `CREATE USER [automation_account_identity_name] FROM EXTERNAL PROVIDER; ALTER ROLE db_owner ADD MEMBER [automation_account_identity_name];`
    - Azure Key Vault: Permissions to get the certificate's public key (e.g., Key Vault Crypto User or custom role with `Microsoft.KeyVault/vaults/certificates/get/action`).
    - Azure Storage Account: `Storage Blob Data Contributor` on the container for uploads/downloads.
- Azure Key Vault with an encryption certificate.
- Target Azure Storage Account and container.
- For `SQLMI-InvokeSqlCmd-Secure-Backup-Runbook.ps1`: The `SqlServer` PowerShell module must be available to the runbook environment (imported into Automation Account modules or on Hybrid Worker).

## Configuration

- Set script parameters within each runbook (e.g., `$SubscriptionId`, `$ResourceGroup`, `$KeyVaultName`, `$SqlServerName`, `$AzureSqlDatabase`, `$StorageAccountName`, `$ContainerName`, `$CertificateName`).

Refer to the main project [README](../../../README.md) for overall architecture and [Decryption Guide](../../../Decryption/README.md) for restoring backups.

## Avantages SQL Managed Instance

- **Backup natif T-SQL** : `BACKUP DATABASE TO URL`  
- **Performance optimale** : Compression SQL Server intégrée  
- **Authentification sécurisée** : `Invoke-Sqlcmd` avec token Azure AD  
- **Format .bak efficace** : Backup natif haute performance  
- **Simplicité** : Une seule commande T-SQL  

## Fonctionnement

### Étape 1 : Connexion Sécurisée
```sql
-- Test de connexion avec identité managée
SELECT DB_NAME() AS CurrentDatabase, 
       CURRENT_USER AS CurrentUser, 
       SYSTEM_USER AS SystemUser;
```

### Étape 2 : Backup T-SQL
```sql
-- Création du credential
CREATE CREDENTIAL [https://storage.blob.core.windows.net/backup]
WITH IDENTITY = 'Managed Identity';

-- Backup vers Blob Storage
BACKUP DATABASE [ma-database]
TO URL = 'https://storage.blob.core.windows.net/backup/ma-database-20250526_123456.bak'
WITH FORMAT, INIT, COMPRESSION;
```

### Étape 3 : Chiffrement
- Chiffrement AES-256 avec clé Azure Key Vault
- Upload du fichier chiffré vers Blob Storage
- Nettoyage des fichiers temporaires

## Monitoring

### Logs Typiques
```
Successfully connected to database: ma-database
Connected as user: AA-restore
T-SQL backup command executed successfully
Backup file verified in storage: 2.4 GB
Backup file downloaded: 2.4 GB
Encrypted file created: 2.4 GB
Operation completed successfully!
```

### Erreurs Courantes
| Erreur | Solution |
|--------|----------|
| `Login failed for user` | Exécuter les commandes CREATE USER |
| `Permission denied` | Vérifier les rôles Azure de l'identité managée |
| `Credential not found` | Le script crée automatiquement le credential |

## Planification

### Backup Quotidien
```powershell
# Créer un schedule dans Azure Automation
New-AzAutomationSchedule -AutomationAccountName "MonAutomation" `
                         -Name "BackupQuotidien" `
                         -StartTime (Get-Date).AddDays(1) `
                         -DayInterval 1
```

## Sécurité

- **Aucun mot de passe stocké** : Identité managée uniquement
- **Chiffrement bout-en-bout** : AES-256 + RSA avec Key Vault
- **Principe du moindre privilège** : Permissions minimales
- **Audit complet** : Logs Azure Automation

## Dépannage

### Test de Connexion
```powershell
# Test manuel de connexion
$token = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
Invoke-Sqlcmd -ServerInstance "mon-sqlmi.database.windows.net" `
              -Database "ma-database" `
              -AccessToken $token `
              -Query "SELECT CURRENT_USER"
```

### Vérification des Permissions
```sql
-- Vérifier les permissions de l'identité
SELECT dp.name as principal_name,
       dp.type_desc as principal_type
FROM sys.database_principals dp
WHERE dp.name LIKE '%AA-restore%';
```

## Performance

- **Compression** : Réduction de 60-80% de la taille
- **Vitesse** : Backup direct vers blob (pas de transit local)
- **Parallélisme** : Utilise les capacités natives SQL Server

## Support

En cas de problème :
1. Vérifiez les logs du runbook Azure Automation
2. Testez la connexion SQL manuellement
3. Validez les permissions de l'identité managée
4. Consultez les métriques Azure Storage 