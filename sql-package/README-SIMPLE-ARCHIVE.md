# Script d'Archivage Simple Azure SQL Database

Script PowerShell simplifié pour archiver des bases de données Azure SQL vers Azure Blob Storage **sans chiffrement** depuis un Azure Automation Runbook.

## 🎯 Objectif

Ce script `simple-archive-runbook.ps1` permet d'exporter une base Azure SQL Database au format BACPAC et de la stocker directement dans Azure Storage, sans chiffrement ni Key Vault.

## 🔧 Deux Méthodes Supportées

### 1. SqlPackage.exe (Recommandé)
- ✅ Plus de contrôle sur l'export
- ✅ Gestion fine des erreurs
- ✅ Téléchargement automatique si absent
- ⚠️ Nécessite plus de ressources temporaires

### 2. API Azure (New-AzSqlDatabaseExport)
- ✅ Export direct vers le storage
- ✅ Pas de fichiers temporaires
- ✅ Intégration native Azure
- ⚠️ Moins de contrôle sur le processus

## 📋 Prérequis

### Azure Automation Account
- System-assigned Managed Identity activée
- Module PowerShell `Az.Accounts`, `Az.Storage`, `Az.Sql` installés
- Module `SqlServer` (pour méthode SqlPackage)

### Permissions RBAC
Pour la Managed Identity de l'Automation Account :

```plaintext
• Reader (scope: Resource Group)
• Storage Blob Data Contributor (scope: Storage Account)
• SQL DB Contributor (scope: SQL Server) OU db_export sur la base
```

### Ressources Azure
- Azure SQL Database
- Azure Storage Account avec conteneur
- Automation Account

## 🚀 Installation

### 1. Configurer l'Automation Account

```powershell
# Dans Azure Portal > Automation Account > Modules
# Installer les modules requis :
- Az.Accounts
- Az.Storage  
- Az.Sql
- SqlServer (pour méthode SqlPackage)
```

### 2. Configurer les Permissions

```bash
# Remplacer par les valeurs réelles
SUBSCRIPTION_ID="votre-subscription-id"
RESOURCE_GROUP="votre-resource-group"  
AUTOMATION_ACCOUNT="votre-automation-account"
STORAGE_ACCOUNT="votre-storage-account"
SQL_SERVER="votre-sql-server"

# Récupérer l'ID de la Managed Identity
PRINCIPAL_ID=$(az automation account show \
  --name $AUTOMATION_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

# Assigner les rôles
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Reader" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"

az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "SQL DB Contributor" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$SQL_SERVER"
```

### 3. Importer le Runbook

1. Azure Portal → Automation Account → Runbooks
2. Create a runbook → PowerShell
3. Copier/coller le contenu de `simple-archive-runbook.ps1`
4. Publier le runbook

## 📝 Configuration

### Paramètres du Runbook

```powershell
# Paramètres obligatoires
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$ResourceGroup = "mon-resource-group"
$SqlServerName = "mon-serveur-sql"                    # Sans .database.windows.net
$AzureSqlDatabase = "ma-base-de-donnees"
$StorageAccountName = "monstorageaccount"
$StorageAccountRG = "mon-storage-resource-group"      # Peut être différent du RG principal
$ContainerName = "backup"

# Paramètre optionnel
$UseMethod = "SqlPackage"                             # "SqlPackage" ou "AzureAPI"
```

## 🎮 Utilisation

### Exécution Manuelle

1. Azure Portal → Automation Account → Runbooks
2. Sélectionner `simple-archive-runbook`
3. Start → Renseigner les paramètres
4. Monitor l'exécution dans les logs

### Exécution Programmée

```powershell
# Créer un schedule pour exécution automatique
New-AzAutomationSchedule -AutomationAccountName "MonAutomationAccount" `
                        -ResourceGroupName "MonResourceGroup" `
                        -Name "BackupQuotidien" `
                        -StartTime (Get-Date).AddDays(1).Date.AddHours(2) `
                        -DayInterval 1

# Lier le runbook au schedule
Register-AzAutomationScheduledRunbook -AutomationAccountName "MonAutomationAccount" `
                                     -ResourceGroupName "MonResourceGroup" `
                                     -RunbookName "simple-archive-runbook" `
                                     -ScheduleName "BackupQuotidien" `
                                     -Parameters @{
                                         SubscriptionId = "votre-subscription-id"
                                         ResourceGroup = "votre-resource-group"
                                         # ... autres paramètres
                                     }
```

## 📊 Résultat

Le script retourne un objet avec les informations suivantes :

```json
{
  "Status": "Success",
  "Message": "Archivage terminé avec succès", 
  "Method": "SqlPackage",
  "Database": "ma-base",
  "Server": "mon-serveur",
  "BackupFile": "ma-base-archive-20250116_143022.bacpac",
  "SasUri": "https://storage.blob.core.windows.net/backup/fichier.bacpac?sas-token",
  "Size": "2.5 GB",
  "Timestamp": "2025-01-16 14:30:22",
  "StorageAccount": "monstorageaccount",
  "Container": "backup"
}
```

## 🔍 Dépannage

### Erreurs Courantes

#### "Failed to connect to database"
```powershell
# Vérifier les permissions sur la base de données
# Se connecter à la base en tant qu'admin et exécuter :
CREATE USER [nom-managed-identity] FROM EXTERNAL PROVIDER;
ALTER ROLE db_export ADD MEMBER [nom-managed-identity];
```

#### "SqlPackage.exe not found"
- Le script télécharge automatiquement SqlPackage
- Vérifier la connectivité Internet du runbook
- Utiliser la méthode "AzureAPI" en alternative

#### "Storage access denied"
```bash
# Vérifier les permissions Storage
az role assignment list --assignee $PRINCIPAL_ID --scope $STORAGE_SCOPE
```

### Monitoring

```powershell
# Vérifier les logs du runbook
Get-AzAutomationJob -AutomationAccountName "MonAutomationAccount" `
                   -ResourceGroupName "MonResourceGroup" `
                   -RunbookName "simple-archive-runbook" | 
    Sort-Object StartTime -Descending | 
    Select-Object -First 5
```

## ⚡ Optimisations

### Performances
- **Bases < 10 GB** : 5-15 minutes
- **Bases 10-100 GB** : 15-45 minutes  
- **Bases > 100 GB** : 45+ minutes

### Recommandations
- Utiliser `SqlPackage` pour bases importantes
- Utiliser `AzureAPI` pour simplicité
- Planifier durant les heures creuses
- Monitorer la taille des archives

## 🔐 Sécurité

- ✅ Authentification Managed Identity uniquement
- ✅ Pas de mot de passe stocké
- ✅ SAS tokens avec expiration limitée (7 jours)
- ✅ Logs auditables dans Azure

## 📞 Support

En cas de problème :
1. Vérifier les logs du runbook dans Azure Portal
2. Tester les permissions RBAC
3. Valider la connectivité réseau
4. Contrôler les quotas Azure Storage

---

**Note** : Ce script ne fait aucun chiffrement. Pour un archivage sécurisé avec chiffrement, utiliser les scripts complets avec Key Vault.
