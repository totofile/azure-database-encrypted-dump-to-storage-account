# SQL Managed Instance - Runbook Sécurisé

Script Azure Automation pour sauvegardes sécurisées et chiffrées de SQL Managed Instance.

## Vue d'ensemble

Ce runbook utilise l'authentification par identité managée pour se connecter sécurisement à SQL Managed Instance et créer des sauvegardes chiffrées automatiquement.

## Fichiers

- **`SQL-Managed-Instance-Secure-Backup-Runbook.ps1`** - Script principal pour SQL Managed Instance
- **`runbook-encrypt-dump-NewAzSqlExport-method.PS1`** - Script alternatif pour Azure SQL Database

## Avantages SQL Managed Instance

- **Backup natif T-SQL** : `BACKUP DATABASE TO URL`  
- **Performance optimale** : Compression SQL Server intégrée  
- **Authentification sécurisée** : `Invoke-Sqlcmd` avec token Azure AD  
- **Format .bak efficace** : Backup natif haute performance  
- **Simplicité** : Une seule commande T-SQL  

## Installation

### 1. Prérequis
- Azure Automation Account avec identité managée système
- SQL Managed Instance
- Azure Key Vault avec certificat
- Azure Storage Account

### 2. Configuration SQL (Obligatoire)
Connectez-vous à votre SQL Managed Instance et exécutez :

```sql
-- Remplacez [AA-restore] par le nom exact de votre identité managée
-- (Ce nom apparaît dans les logs du runbook)
CREATE USER [AA-restore] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [AA-restore];
```

**Note** : Le nom de l'identité managée est affiché dans les logs lors du test de connexion.

### 3. Permissions Azure
Votre identité managée doit avoir :
- **Storage Blob Data Contributor** sur le Storage Account
- **Key Vault Crypto User** sur le Key Vault  
- **Lecteur** sur le Resource Group

### 4. Import du Runbook
1. Azure Portal → Automation Account
2. Runbooks → Import a runbook
3. Sélectionnez `SQL-Managed-Instance-Secure-Backup-Runbook.ps1`
4. Configurez les paramètres

## Configuration

### Paramètres du Runbook
```powershell
$SubscriptionId = "votre-subscription-id"
$ResourceGroup = "votre-resource-group"
$KeyVaultName = "votre-key-vault"
$SqlServerName = "votre-sqlmi-instance"        # Sans .database.windows.net
$AzureSqlDatabase = "votre-database"
$StorageAccountName = "votre-storage-account"
$ContainerName = "backup"
$CertificateName = "votre-certificat-encryption"
```

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