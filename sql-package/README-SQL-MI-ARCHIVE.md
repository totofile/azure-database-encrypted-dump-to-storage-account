# Archive Azure SQL Managed Instance - Runbook

Script PowerShell optimisé pour archiver des bases de données **Azure SQL Managed Instance** vers Azure Storage depuis un Azure Automation Runbook.

## ✅ Méthodes Supportées pour SQL MI

### 1. T-SQL BACKUP DATABASE (Recommandé)
- ✅ **Méthode native** SQL Server
- ✅ **Performance optimale** avec compression
- ✅ **Format .bak** standard 
- ✅ **Backup direct** vers Azure Storage
- ✅ **Managed Identity** supportée

### 2. SqlPackage.exe
- ✅ **Export BACPAC** standard
- ✅ **Téléchargement automatique** si absent
- ✅ **Access token** avec Managed Identity
- ⚠️ Plus lent pour grandes bases

## 📋 Configuration Requise

### Modules PowerShell (Automation Account)
```powershell
# Modules requis dans l'Automation Account
- Az.Accounts
- Az.Storage
- Az.Sql
- SqlServer  # OBLIGATOIRE pour les deux méthodes
```

### Permissions RBAC
Pour la **Managed Identity** de l'Automation Account :

```bash
# Permissions minimales requises
- Reader (Resource Group)
- Storage Blob Data Contributor (Storage Account)
- SQL Managed Instance Contributor (SQL MI) OU permissions DB spécifiques
```

### Configuration SQL Managed Instance
Se connecter à SQL MI en tant qu'admin et exécuter :

```sql
-- Remplacer [NOM-MANAGED-IDENTITY] par le nom de votre Automation Account
CREATE USER [NOM-MANAGED-IDENTITY] FROM EXTERNAL PROVIDER;
ALTER ROLE db_backupoperator ADD MEMBER [NOM-MANAGED-IDENTITY];
GRANT ALTER ANY CREDENTIAL TO [NOM-MANAGED-IDENTITY];

-- Optionnel : Pour SqlPackage, ajouter aussi
ALTER ROLE db_datareader ADD MEMBER [NOM-MANAGED-IDENTITY];
```

## 🚀 Utilisation

### Paramètres par Défaut (Vos Valeurs)
Le script est pré-configuré avec :

```powershell
$SubscriptionId = "d81eb1ff-2fdf-4280-bad9-5c180d51db77"
$ResourceGroup = "theophile.faugeras_rg-00"
$SqlServerName = "srv-poc-entra-auth"
$AzureSqlDatabase = "db-poc-auth"
$StorageAccountName = "fgaccount"
$StorageAccountRG = "theophile.faugeras_rg-00"
$ContainerName = "backup"
$UseMethod = "TSqlBackup"  # ou "SqlPackage"
```

### Exécution Runbook

1. **Azure Portal** → Automation Account → Runbooks
2. **Import** le script `archive-sql-package.ps1`
3. **Publier** le runbook
4. **Start** avec paramètres (ou utiliser les valeurs par défaut)

### Test Local (Optionnel)
```powershell
# Test avec vos paramètres
.\archive-sql-package.ps1 -UseMethod "TSqlBackup"

# Test SqlPackage
.\archive-sql-package.ps1 -UseMethod "SqlPackage"
```

## 📊 Résultats

### Méthode T-SQL BACKUP
```json
{
  "Status": "Success",
  "Method": "TSqlBackup",
  "BackupFile": "db-poc-auth-sqlmi-20250116_143022.bak",
  "FileType": "BAK",
  "Size": "1.2 GB"
}
```

### Méthode SqlPackage
```json
{
  "Status": "Success", 
  "Method": "SqlPackage",
  "BackupFile": "db-poc-auth-sqlmi-20250116_143022.bacpac",
  "FileType": "BACPAC",
  "Size": "800 MB"
}
```

## 🔧 Dépannage

### Erreur "Failed to connect to SQL MI"
```sql
-- Vérifier l'utilisateur dans SQL MI
SELECT name, type_desc, authentication_type_desc 
FROM sys.database_principals 
WHERE name = 'NOM-DE-VOTRE-AUTOMATION-ACCOUNT';

-- Si absent, créer l'utilisateur
CREATE USER [NOM-AUTOMATION-ACCOUNT] FROM EXTERNAL PROVIDER;
```

### Erreur "SqlPackage download failed"
```powershell
# Solution : Utiliser T-SQL BACKUP à la place
$UseMethod = "TSqlBackup"
```

### Erreur "Storage access denied"
```bash
# Vérifier les permissions storage
az role assignment list --assignee MANAGED-IDENTITY-ID --scope STORAGE-ACCOUNT-SCOPE
```

### Erreur "Credential creation failed"
```sql
-- Donner les droits pour créer des credentials
GRANT ALTER ANY CREDENTIAL TO [NOM-MANAGED-IDENTITY];
```

## ⚡ Performances

### T-SQL BACKUP (Recommandé)
- **Bases < 10 GB** : 2-5 minutes
- **Bases 10-100 GB** : 5-20 minutes  
- **Bases > 100 GB** : 20+ minutes

### SqlPackage
- **Bases < 10 GB** : 5-15 minutes
- **Bases 10-100 GB** : 15-45 minutes
- **Bases > 100 GB** : 45+ minutes

## 🔄 Automatisation

### Schedule Quotidien
```powershell
# Azure Portal > Automation Account > Schedules
# Créer un schedule pour exécution automatique à 2h du matin
Name: "BackupQuotidienSQLMI"
Frequency: Daily
Start time: 02:00
Timezone: (UTC+01:00) Paris
```

### Lier au Runbook
```powershell
# Azure Portal > Runbooks > archive-sql-package > Schedules
# Link schedule : BackupQuotidienSQLMI
# Parameters : utiliser les valeurs par défaut
```

## 🎯 Recommandations

### Pour Production
- ✅ Utiliser **TSqlBackup** (plus rapide, plus fiable)
- ✅ Programmer durant les **heures creuses**
- ✅ Monitorer la **taille des archives**
- ✅ Configurer des **alertes** sur échecs

### Pour Dev/Test
- ✅ Utiliser **SqlPackage** pour portabilité
- ✅ Archives plus **compactes** (.bacpac)
- ✅ Compatible avec **import** sur autres environnements

## 📞 Support

En cas de problème :
1. **Logs** : Azure Portal > Automation Account > Jobs
2. **Connectivité** : Tester depuis Azure Cloud Shell
3. **Permissions** : Vérifier via `az role assignment list`
4. **SQL MI** : Tester connexion Managed Identity manuellement

---

**Note** : Ce script est optimisé pour **Azure SQL Managed Instance**. Pour Azure SQL Database standard, des adaptations seraient nécessaires.
