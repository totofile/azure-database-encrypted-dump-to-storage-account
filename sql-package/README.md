# Azure SQL Managed Instance - Archive avec SqlPackage (Runbook)

Ce dépôt fournit un script PowerShell `sql-package/archive-sql-package.ps1` pour archiver une base Azure SQL Managed Instance au format BACPAC vers Azure Blob Storage, à exécuter depuis un Azure Automation Runbook ou un environnement PowerShell avec Managed Identity. AUCUN chiffrement n'est effectué.

## ✅ Points clés
- Utilise exclusivement SqlPackage.exe (compatible access token/Managed Identity)
- Télécharge automatiquement SqlPackage si absent
- Upload direct du fichier .bacpac vers Azure Storage
- Nettoyage des fichiers temporaires

## 📦 Script
- Fichier: `sql-package/archive-sql-package.ps1`
- Sortie: `nom-base-sqlmi-YYYYMMDD_HHMMSS.bacpac`

## 🔐 Prérequis et permissions

### 1) Control-plane (RBAC Azure)
Assigner à la Managed Identity de la ressource qui exécute le script (ex: Automation Account) les rôles suivants:
- Reader sur le Resource Group (ou portée minimale requise)
- Storage Blob Data Contributor sur le Storage Account cible

Optionnel si vous listez/gérez des serveurs: Reader sur le serveur SQL (ressource Azure).

### 2) Data-plane (SQL - à exécuter dans la base)
L’utilisateur Managed Identity doit exister dans la base cible et disposer d’un accès en lecture pour l’export BACPAC:

```sql
CREATE USER [nom-managed-identity] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [nom-managed-identity];
```

Remplacez `nom-managed-identity` par le nom affiché de l’identité managée (Automation Account, VM, etc.).

## 🧰 Modules requis (Automation Account)
- Az.Accounts
- Az.Storage
- Az.Sql
- SqlServer

## ⚙️ Paramètres par défaut (modifiez selon vos besoins)

```powershell
param(
    [string]$SubscriptionId = "d81eb1ff-2fdf-4280-bad9-5c180d51db77",
    [string]$ResourceGroup = "theophile.faugeras_rg-00",
    [string]$SqlServerName = "srv-poc-entra-auth",   # sans suffixe
    [string]$AzureSqlDatabase = "db-poc-auth",
    [string]$StorageAccountName = "fgaccount",
    [string]$StorageAccountRG = "theophile.faugeras_rg-00",
    [string]$ContainerName = "backup"
)
```

## 🚀 Utilisation (Runbook)
1. Azure Portal → Automation Account → Runbooks → Importer le contenu de `archive-sql-package.ps1`
2. Publier le runbook
3. Lancer avec les paramètres voulus (ou ceux par défaut)

## 🧪 Test local (optionnel)
```powershell
# Ouvrir une session avec identité (si applicable)
Connect-AzAccount

# Exécuter
./sql-package/archive-sql-package.ps1
```

## 📊 Résultat retourné
```json
{
  "Status": "Success",
  "Message": "Archivage SQL Managed Instance terminé avec succès",
  "Method": "SqlPackage",
  "Database": "db-poc-auth",
  "Server": "srv-poc-entra-auth",
  "BackupFile": "db-poc-auth-sqlmi-20250116_143022.bacpac",
  "SasUri": "https://...",
  "Size": "800 MB",
  "Timestamp": "2025-01-16 14:30:22",
  "StorageAccount": "fgaccount",
  "Container": "backup",
  "FileType": "BACPAC"
}
```

## 🔍 Dépannage
- "Failed to connect to SQL MI" → Vérifier les commandes SQL ci-dessus (Data-plane) et l’accès réseau
- "SqlPackage.exe not found" → Le script télécharge automatiquement; vérifier la connectivité sortante
- "Storage access denied" → Vérifier le rôle "Storage Blob Data Contributor" à la bonne portée

## ⚠️ Notes
- Ce script ne chiffre pas les archives
- Conçu pour SQL Managed Instance via SqlPackage (pas de BACKUP DATABASE vers URL)
