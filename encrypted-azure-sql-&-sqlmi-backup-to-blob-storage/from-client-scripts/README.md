# Scripts Client - Exécution Locale

Scripts PowerShell pour sauvegardes sécurisées depuis un poste de travail ou serveur.

## Vue d'ensemble

Ces scripts permettent d'exécuter des sauvegardes chiffrées depuis n'importe quel poste Windows avec PowerShell, en utilisant l'authentification Azure AD interactive ou service principal.

## Fichiers

- **`connect-sql-paas.ps1`** - Test de connectivité Azure SQL avec Azure AD
- **`encrypt-dump.ps1`** - Script principal de backup et chiffrement (legacy)

## Fonctionnalités

- **Authentification Azure AD** : Connexion interactive ou service principal  
- **Export BACPAC** : Compatible Azure SQL Database  
- **Chiffrement local** : AES-256 avec certificats Key Vault  
- **Upload sécurisé** : Vers Azure Blob Storage  
- **Flexible** : Exécution depuis n'importe quel poste  

## Installation

### Prérequis
- PowerShell 5.1 ou supérieur
- Modules Azure PowerShell :
  ```powershell
  Install-Module Az.Accounts, Az.KeyVault, Az.Storage, Az.Sql, SqlServer -Force
  ```
- Permissions Azure AD sur les ressources cibles

### Configuration
```powershell
# Variables de configuration
$SubscriptionId = "votre-subscription-id"
$TenantId = "votre-tenant-id"
$ResourceGroup = "votre-resource-group"
$SqlServerName = "votre-sql-server"
$AzureSqlDatabase = "votre-database"
$KeyVaultName = "votre-key-vault"
$StorageAccountName = "votre-storage-account"
```

## Usage

### Test de Connectivité
```powershell
# Tester la connexion Azure SQL
.\connect-sql-paas.ps1
```

### Backup Complet
```powershell
# Exécuter le backup et chiffrement
.\encrypt-dump.ps1
```

## Authentification

### Authentification Interactive
```powershell
# Connexion avec navigateur (recommandé pour tests)
Connect-AzAccount -TenantId $TenantId
```

### Service Principal
```powershell
# Connexion automatisée
$ClientId = "votre-app-id"
$ClientSecret = "votre-client-secret"
$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)
Connect-AzAccount -ServicePrincipal -Credential $Credential -TenantId $TenantId
```

## Workflow

### 1. Connexion Azure
- Authentification Azure AD
- Sélection de la subscription
- Validation des permissions

### 2. Export Database
- Export BACPAC via API Azure
- Téléchargement du fichier
- Validation de l'intégrité

### 3. Chiffrement
- Récupération du certificat Key Vault
- Chiffrement AES-256 + RSA
- Création du fichier `.encrypted`

### 4. Upload Sécurisé
- Upload vers Azure Blob Storage
- Génération d'URL de téléchargement avec SAS
- Nettoyage des fichiers temporaires

## Configuration Avancée

### Variables d'Environnement
```powershell
# Optionnel : utiliser des variables d'environnement
$env:AZURE_SUBSCRIPTION_ID = "votre-subscription-id"
$env:AZURE_TENANT_ID = "votre-tenant-id"
$env:KEYVAULT_NAME = "votre-key-vault"
```

### Personnalisation du Nommage
```powershell
# Format des fichiers de backup
$BackupFileName = "$AzureSqlDatabase-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
$EncryptedFileName = "$BackupFileName.encrypted"
```

## Sécurité

- **Authentification forte** : Azure AD uniquement
- **Chiffrement bout-en-bout** : Aucune donnée en clair
- **Rotation automatique** : Certificats Key Vault
- **Audit complet** : Logs Azure Activity

## Monitoring

### Logs Typiques
```
Connected to Azure subscription: Production
Export request submitted: request-id-12345
BACPAC export completed: 1.2 GB
Certificate retrieved from Key Vault: cert-encryption
File encrypted successfully: 1.2 GB
Upload completed: https://storage.blob.core.windows.net/backup/file.encrypted
SAS URL generated (valid 7 days)
```

### Erreurs Courantes
| Erreur | Solution |
|--------|----------|
| `Insufficient permissions` | Vérifier les rôles Azure AD |
| `Export timeout` | Augmenter la timeout ou utiliser une base plus petite |
| `Certificate not found` | Vérifier le nom du certificat Key Vault |

## Dépannage

### Test de Permissions
```powershell
# Vérifier les permissions Azure
Get-AzRoleAssignment -SignInName "user@domain.com" | 
    Where-Object {$_.RoleDefinitionName -like "*SQL*" -or $_.RoleDefinitionName -like "*Storage*"}
```

### Test de Connectivité SQL
```powershell
# Test de connexion directe
$token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($account, $environment, $tenantId, $null, "Never", $null, "https://database.windows.net/").AccessToken
Invoke-Sqlcmd -ServerInstance "$SqlServerName.database.windows.net" -Database $AzureSqlDatabase -AccessToken $token -Query "SELECT @@VERSION"
```

## Performance

- **Temps moyen** : 5-15 minutes selon la taille de la base
- **Bande passante** : Limitée par la connexion Internet
- **Parallélisme** : Export et chiffrement séquentiels

## Comparaison avec Runbook

| Critère | Scripts Client | Azure Runbook |
|---------|---------------|---------------|
| **Déploiement** | Simple | Configuration Azure |
| **Sécurité** | Utilisateur local | Identité managée |
| **Planification** | Tâches Windows | Azure Automation |
| **Monitoring** | Local | Logs Azure |
| **Coût** | Gratuit | Coût d'exécution |

## Support

En cas de problème :
1. Vérifiez la connexion Azure avec `Get-AzContext`
2. Testez les permissions avec `Get-AzRoleAssignment`
3. Validez la connectivité SQL avec `connect-sql-paas.ps1`
4. Consultez les logs PowerShell détaillés 