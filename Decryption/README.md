# Déchiffrement des Sauvegardes

Scripts pour déchiffrer et restaurer les sauvegardes chiffrées créées par les runbooks Azure.

## Vue d'ensemble

Ce dossier contient les outils nécessaires pour déchiffrer les fichiers de sauvegarde chiffrés avec Azure Key Vault et les restaurer sur n'importe quel serveur SQL compatible.

## Fichiers

- **`decrypt.ps1`** - Script principal de déchiffrement

## Fonctionnalités

- **Déchiffrement sécurisé** : Utilise les certificats Azure Key Vault  
- **Multi-format** : Compatible .bak (SQL MI) et .bacpac (Azure SQL DB)  
- **Portabilité** : Restoration sur n'importe quel SQL Server  
- **Validation** : Vérification de l'intégrité des données  
- **Flexibilité** : Déchiffrement local ou cloud  

## Prérequis

- PowerShell 5.1 ou supérieur
- Modules Azure PowerShell :
  - Az.Accounts
  - Az.KeyVault
- Accès au Key Vault et au certificat utilisé pour le chiffrement
- Le fichier de sauvegarde chiffré (.bak.encrypted ou .bacpac.encrypted)

## Usage Rapide

### Déchiffrement Simple
```powershell
# Déchiffrer un fichier de sauvegarde
.\decrypt.ps1 -EncryptedFile "database-20250526_123456.bak.encrypted" `
              -KeyVaultName "mon-key-vault" `
              -CertificateName "cert-encryption"
```

### Avec Restauration Automatique
```powershell
# Déchiffrer et restaurer directement
.\decrypt.ps1 -EncryptedFile "database.bak.encrypted" `
              -KeyVaultName "mon-key-vault" `
              -CertificateName "cert-encryption" `
              -SqlServer "mon-serveur-sql" `
              -DatabaseName "database-restored" `
              -AutoRestore
```

## Authentification

### Authentification Interactive
```powershell
# Connexion avec navigateur (recommandé)
Connect-AzAccount
.\decrypt.ps1 -EncryptedFile "fichier.encrypted" -KeyVaultName "kv"
```

### Service Principal
```powershell
# Authentification automatisée
$ClientId = "app-id"
$ClientSecret = "secret"
$TenantId = "tenant-id"

$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential = New-Object PSCredential($ClientId, $SecureSecret)
Connect-AzAccount -ServicePrincipal -Credential $Credential -TenantId $TenantId

.\decrypt.ps1 -EncryptedFile "fichier.encrypted" -KeyVaultName "kv"
```

## Workflow de Déchiffrement

### 1. Téléchargement du Fichier Chiffré
```powershell
# Télécharger depuis Azure Blob Storage
$StorageContext = New-AzStorageContext -StorageAccountName "storage" -UseConnectedAccount
Get-AzStorageBlobContent -Container "backup" `
                         -Blob "database.bak.encrypted" `
                         -Destination "C:\Temp\" `
                         -Context $StorageContext
```

### 2. Déchiffrement
```powershell
# Le script effectue automatiquement :
# - Récupération du certificat Key Vault
# - Déchiffrement de la clé AES avec RSA
# - Déchiffrement du fichier avec AES-256
# - Validation de l'intégrité
```

### 3. Restauration
```powershell
# Pour fichier .bak (SQL Managed Instance)
RESTORE DATABASE [DatabaseName] 
FROM DISK = 'C:\Temp\database.bak'
WITH REPLACE, STATS = 10;

# Pour fichier .bacpac (Azure SQL Database)
SqlPackage.exe /Action:Import /SourceFile:"database.bacpac" /TargetServerName:"serveur" /TargetDatabaseName:"database"
```

## Paramètres Détaillés

### Paramètres Obligatoires
```powershell
-EncryptedFile      # Chemin vers le fichier chiffré
-KeyVaultName       # Nom du Key Vault contenant le certificat
-CertificateName    # Nom du certificat de déchiffrement
```

### Paramètres Optionnels
```powershell
-OutputPath         # Dossier de sortie (défaut: même dossier)
-SqlServer          # Serveur SQL pour restauration automatique
-DatabaseName       # Nom de la base après restauration
-AutoRestore        # Déclenche la restauration automatique
-OverwriteExisting  # Remplace les fichiers existants
-KeepDecrypted      # Conserve le fichier déchiffré après restauration
```

## Sécurité

### Permissions Requises
- **Key Vault Crypto User** : Pour accéder aux certificats
- **Storage Blob Data Reader** : Pour télécharger les fichiers chiffrés
- **sysadmin** ou **dbcreator** : Pour la restauration SQL Server

### Bonnes Pratiques
- Utilisez des identités managées quand c'est possible
- Limitez l'accès aux certificats de déchiffrement
- Supprimez les fichiers temporaires après usage
- Auditez tous les accès aux sauvegardes

## Dépannage

### Erreurs Courantes

| Erreur | Cause | Solution |
|--------|-------|----------|
| `Certificate not found` | Certificat supprimé/inexistant | Vérifier le nom dans Key Vault |
| `Decryption failed` | Mauvais certificat utilisé | Utiliser le certificat de chiffrement |
| `File corrupted` | Fichier endommagé | Re-télécharger depuis le blob |
| `Access denied` | Permissions insuffisantes | Vérifier les rôles Azure |

### Validation de l'Intégrité
```powershell
# Le script vérifie automatiquement :
# - Taille du fichier déchiffré
# - Hash de contrôle (si disponible)
# - Format du fichier (.bak/.bacpac)
```

### Mode Debug
```powershell
# Activer les logs détaillés
.\decrypt.ps1 -EncryptedFile "file.encrypted" -KeyVaultName "kv" -Verbose
```

## Performance

### Temps de Déchiffrement
- **Petite base** (< 1 GB) : 1-2 minutes
- **Base moyenne** (1-10 GB) : 3-10 minutes  
- **Grande base** (10+ GB) : 10+ minutes

### Optimisations
- Utilisez un SSD pour les fichiers temporaires
- Assurez-vous d'avoir suffisamment d'espace disque (2x la taille du fichier)
- Exécutez le déchiffrement sur une machine puissante

## Support

En cas de problème :
1. Vérifiez les permissions Key Vault avec `Get-AzKeyVaultAccessPolicy`
2. Testez la connectivité Azure avec `Test-AzKeyVaultConnection`
3. Validez l'intégrité du fichier chiffré
4. Consultez les logs détaillés avec `-Verbose`
5. Vérifiez l'espace disque disponible 