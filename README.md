# Secure Azure SQL Backup & Encryption

Solution sécurisée pour sauvegarder et chiffrer les bases de données Azure SQL avec Azure Key Vault.

## Vue d'ensemble

Ce repository contient des scripts PowerShell pour créer des sauvegardes sécurisées et chiffrées de bases de données Azure SQL. Les sauvegardes sont chiffrées avec des certificats Azure Key Vault et stockées dans Azure Blob Storage.

## Structure du Repository

```
encrypt-dump/
├── README.md                                    # Documentation principale
├── SQL-Managed-Instance-Runbook/               # Solution recommandée
│   ├── SQL-Managed-Instance-Secure-Backup-Runbook.ps1  # Script principal
│   └── runbook-encrypt-dump-NewAzSqlExport-method.PS1   # Alternative Azure SQL DB
├── Client-Scripts/                             # Scripts locaux
│   └── connect-sql-paas.ps1                    # Test connectivité
└── Decryption/                                 # Outils de déchiffrement
    ├── decrypt.ps1                             # Script principal
    └── README.md                               # Guide déchiffrement
```

## Solutions Disponibles

### SQL Managed Instance (Recommandé)
**Script principal :** `SQL-Managed-Instance-Runbook/SQL-Managed-Instance-Secure-Backup-Runbook.ps1`

- **Authentification sécurisée** : Identité managée Azure Automation  
- **Backup natif** : Commande T-SQL `BACKUP DATABASE` standard  
- **Performance optimale** : Compression intégrée SQL Server  
- **Format .bak** : Backup natif haute performance  

### Azure SQL Database
**Script :** `SQL-Managed-Instance-Runbook/runbook-encrypt-dump-NewAzSqlExport-method.PS1`

- **Limitations** : Export BACPAC via API Azure (plus lent)  
- **Complexité** : Authentification plus complexe  

## Installation Rapide

### Prérequis
- Azure Automation Account avec identité managée système
- SQL Managed Instance ou Azure SQL Database
- Azure Key Vault avec certificat
- Azure Storage Account

### Configuration SQL (Obligatoire)
Connectez-vous à votre base de données et exécutez :

```sql
-- Remplacez [AA-restore] par le nom de votre identité managée
CREATE USER [AA-restore] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [AA-restore];
```

### Déploiement
1. Importez le script dans Azure Automation
2. Configurez les paramètres dans le runbook
3. Programmez l'exécution automatique

## Sécurité

- **Authentification sans mot de passe** : Identité managée Azure
- **Chiffrement AES-256** : Clés gérées par Azure Key Vault  
- **Rotation automatique** : Certificats Azure Key Vault
- **Principe du moindre privilège** : Permissions minimales

## Comparaison des Solutions

| Critère | SQL Managed Instance | Azure SQL Database |
|---------|---------------------|-------------------|
| **Performance** | Excellent | Bon |
| **Simplicité** | Très simple | Complexe |
| **Format** | .bak (natif) | .bacpac (export) |
| **Taille** | Compressé | Plus volumineux |
| **Vitesse** | Rapide | Plus lent |

## Usage

### Pour SQL Managed Instance
```powershell
# Configuration dans le runbook
$SqlServerName = "votre-sqlmi-instance"
$AzureSqlDatabase = "votre-database"
$StorageAccountName = "votre-storage"
$KeyVaultName = "votre-keyvault"
```

### Exécution
Le runbook peut être exécuté :
- Manuellement depuis le portail Azure
- Automatiquement via schedule
- Déclenché par webhook

## Documentation Détaillée

- [Guide SQL Managed Instance](SQL-Managed-Instance-Runbook/README.md)
- [Guide Déchiffrement](Decryption/README.md)

## Support

Pour des questions ou problèmes :
1. Vérifiez les logs Azure Automation
2. Validez les permissions de l'identité managée
3. Testez la connectivité SQL avec `Invoke-Sqlcmd`

## Licence

Ce projet est sous licence MIT. Voir le fichier LICENSE pour plus de détails.
