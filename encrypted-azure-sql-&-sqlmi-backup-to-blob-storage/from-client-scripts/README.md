# Client-Side Backup & Encryption Scripts

PowerShell scripts for manual backup (.bacpac export), encryption, and upload of Azure SQL Databases from a local machine.

## Scripts & Functionality

- **`encrypt-dump.ps1` (Main Script)**:
    - Connects to Azure, exports an Azure SQL Database to a `.bacpac` file.
    - Encrypts the `.bacpac` using an Azure Key Vault certificate (AES-256).
    - Uploads the encrypted `.bacpac.encrypted` file to Azure Blob Storage.
    - Can optionally create the Key Vault and certificate if they don't exist.
- **`connect-sql-paas.ps1`**: Tests Azure SQL DB connectivity using Entra ID.
- **`create-akv-cert.ps1`**: Tests Key Vault certificate creation.

## Prerequisites

- PowerShell 5.1+
- Azure PowerShell Modules: `Az.Accounts`, `Az.KeyVault`, `Az.Storage`, `Az.Sql`, `SqlServer`.
  ```powershell
  # Install if missing (run as admin or use -Scope CurrentUser)
  Install-Module Az.Accounts, Az.KeyVault, Az.Storage, Az.Sql, SqlServer -Force
  ```
- **Azure AD Identity (User/Service Principal) Permissions**:
    - Key Vault: Create/access certificates.
    - Azure SQL DB: Export database (e.g., Contributor role).
    - Azure Storage: Write to Blob container (e.g., Storage Blob Data Contributor).

## Basic Usage (`encrypt-dump.ps1`)

1.  **Authenticate to Azure**: `Connect-AzAccount -TenantId "your-tenant-id"` (interactive or SP).
2.  **Run the script** (review internal parameters or pass them):
    ```powershell
    .\encrypt-dump.ps1 -SubscriptionId "your-sub-id" `
                       -ResourceGroup "your-rg" `
                       -KeyVaultName "your-kv" `
                       -SqlServerName "yourserver.database.windows.net" `
                       -AzureSqlDatabase "yourdb" `
                       -StorageAccountName "yourstorage" `
                       -ContainerName "backups" `
                       # ... other parameters as needed (Location, CertificateName, etc.)
    ```

Refer to script comments for detailed parameters. For decryption, see the main [Decryption Guide](../../../Decryption/README.md).

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