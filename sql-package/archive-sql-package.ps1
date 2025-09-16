<#
.SYNOPSIS
    Runbook pour archiver une base Azure SQL Managed Instance vers Azure Storage
.DESCRIPTION
    Ce script runbook utilise SqlPackage.exe pour exporter une base SQL MI au format BACPAC
    vers Azure Blob Storage. Il supporte l'authentification par Managed Identity.
    
    IMPORTANT: T-SQL BACKUP DATABASE ne fonctionne PAS avec des URLs externes sur SQL MI.
    Seul SqlPackage est supporté pour l'export vers Azure Storage.
.NOTES
    Auteur: Assistant IA
    Date: 2025-01-16
    PowerShell: 7.2
    
    Prérequis SQL Managed Instance :
    - Automation Account avec Managed Identity
    - Module SqlServer installé dans l'Automation Account
    - RBAC : Reader sur RG, Storage Blob Data Contributor
    - SqlPackage.exe (téléchargé automatiquement si absent)
#>

param(
    [string]$SubscriptionId = "d81eb1ff-2fdf-4280-bad9-5c180d51db77",
    [string]$ResourceGroup = "theophile.faugeras_rg-00",
    [string]$SqlServerName = "srv-poc-entra-auth",                     # Server name without suffix
    [string]$AzureSqlDatabase = "db-poc-auth",
    [string]$StorageAccountName = "fgaccount",
    [string]$StorageAccountRG = "theophile.faugeras_rg-00",
    [string]$ContainerName = "backup"
)

# Configuration minimale pour runbooks
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Fonction de logging simplifiée
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "$timestamp - [$Level] $Message"
}

function Format-FileSize {
    param([long]$Size)
    if ($Size -gt 1GB) { return "$([math]::Round($Size / 1GB, 2)) GB" }
    if ($Size -gt 1MB) { return "$([math]::Round($Size / 1MB, 2)) MB" }
    if ($Size -gt 1KB) { return "$([math]::Round($Size / 1KB, 2)) KB" }
    return "$Size Bytes"
}

function Export-WithSqlPackage {
    param(
        [string]$ServerName,
        [string]$Database,
        [string]$AccessToken,
        [string]$OutputPath
    )
    
    Write-Log "Méthode SqlPackage sélectionnée"
    
    # Recherche de SqlPackage.exe
    $sqlPackagePaths = @(
        "${env:ProgramFiles}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
        "${env:ProgramFiles(x86)}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe"
    )
    
    $sqlPackageExe = $null
    foreach ($path in $sqlPackagePaths) {
        if (Test-Path $path) {
            $sqlPackageExe = $path
            break
        }
    }
    
    if (-not $sqlPackageExe) {
        Write-Log "SqlPackage.exe introuvable, téléchargement depuis Microsoft..."
        
        $tempDir = [System.IO.Path]::GetTempPath()
        $sqlPackageZipPath = Join-Path -Path $tempDir -ChildPath "sqlpackage-$(Get-Date -Format 'yyyyMMdd').zip"
        $sqlPackageExtractPath = Join-Path -Path $tempDir -ChildPath "sqlpackage-extracted"
        
        try {
            # URL directe pour le téléchargement (plus fiable pour Automation Account)
            $downloadUrl = "https://aka.ms/sqlpackage-windows"
            Write-Log "Téléchargement de SqlPackage depuis : $downloadUrl"
            
            # Téléchargement avec options spécifiques pour Automation Account
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "PowerShell-Automation-Account")
            $webClient.DownloadFile($downloadUrl, $sqlPackageZipPath)
            $webClient.Dispose()
            
            Write-Log "Fichier téléchargé : $(Format-FileSize (Get-Item $sqlPackageZipPath).Length)"
            
            # Extraction
            Write-Log "Extraction de SqlPackage..."
            if (Test-Path $sqlPackageExtractPath) {
                Remove-Item -Path $sqlPackageExtractPath -Recurse -Force
            }
            Expand-Archive -Path $sqlPackageZipPath -DestinationPath $sqlPackageExtractPath -Force
            
            # Recherche du fichier exécutable
            $sqlPackageExe = Get-ChildItem -Path $sqlPackageExtractPath -Filter "sqlpackage.exe" -Recurse | Select-Object -First 1 -ExpandProperty FullName
            
            if (-not $sqlPackageExe -or -not (Test-Path $sqlPackageExe)) {
                throw "SqlPackage.exe non trouvé après extraction"
            }
            
            Write-Log "SqlPackage.exe extrait avec succès"
        }
        catch {
            Write-Log "Échec du téléchargement/extraction de SqlPackage.exe : $_" -Level "ERROR"
            Write-Log "SOLUTION : Pré-installer SqlPackage dans l'Automation Account ou utiliser la méthode TSqlBackup" -Level "ERROR"
            throw "SqlPackage.exe requis mais non disponible"
        }
        finally {
            # Nettoyage du fichier zip
            if (Test-Path $sqlPackageZipPath) {
                Remove-Item -Path $sqlPackageZipPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Write-Log "SqlPackage.exe trouvé : $sqlPackageExe"
    
    # Construction des arguments SqlPackage
    $sqlPackageArgs = @(
        "/Action:Export",
        "/SourceServerName:$ServerName",
        "/SourceDatabaseName:$Database",
        "/SourceTrustServerCertificate:True",
        "/SourceTimeout:3600",
        "/TargetFile:$OutputPath",
        "/AccessToken:$AccessToken"
    )
    
    Write-Log "Démarrage de l'export avec SqlPackage..."
    Write-Log "Serveur source : $ServerName"
    Write-Log "Base source : $Database"
    Write-Log "Fichier cible : $OutputPath"
    
    try {
        $process = Start-Process -FilePath $sqlPackageExe -ArgumentList $sqlPackageArgs -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -ne 0) {
            throw "SqlPackage.exe a retourné le code d'erreur : $($process.ExitCode)"
        }
        
        Write-Log "Export SqlPackage terminé avec succès"
        
        if (Test-Path $OutputPath) {
            $fileSize = (Get-Item $OutputPath).Length
            Write-Log "Fichier BACPAC créé : $(Format-FileSize $fileSize)"
            return $true
        } else {
            throw "Le fichier BACPAC n'a pas été créé"
        }
    }
    catch {
        Write-Log "Erreur durant l'export SqlPackage : $_" -Level "ERROR"
        throw
    }
}

# Note: T-SQL BACKUP DATABASE ne fonctionne PAS avec des URLs externes sur Azure SQL MI
# Cette fonction a été supprimée car non supportée par la plateforme

# DÉBUT DU RUNBOOK
Write-Log "=== ARCHIVAGE AZURE SQL MANAGED INSTANCE avec SqlPackage ==="
Write-Log "Base de données : $AzureSqlDatabase"
Write-Log "Serveur : $SqlServerName"
Write-Log "Méthode : SqlPackage.exe (seule méthode supportée pour SQL MI)"
Write-Log "Format de sortie : BACPAC"

try {
    # Connexion avec Managed Identity
    Write-Log "Connexion à Azure avec Managed Identity..."
    Connect-AzAccount -Identity
    
    # Vérification du contexte
    $context = Get-AzContext
    Write-Log "Compte connecté : $($context.Account.Id)"
    
    # Sélection de l'abonnement
    Select-AzSubscription -SubscriptionId $SubscriptionId
    Write-Log "Abonnement sélectionné : $SubscriptionId"
    
    # Configuration du nom complet du serveur
    if (-not $SqlServerName.Contains('.database.windows.net')) {
        $fullServerName = "$SqlServerName.database.windows.net"
    } else {
        $fullServerName = $SqlServerName
    }
    
    Write-Log "Serveur SQL complet : $fullServerName"
    
    # Accès au compte de stockage
    Write-Log "Configuration du stockage : $StorageAccountName"
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName
    $storageContext = $storageAccount.Context
    
    # Vérification/création du conteneur
    $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    if (-not $container) {
        Write-Log "Création du conteneur : $ContainerName"
        New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off
    } else {
        Write-Log "Conteneur existant : $ContainerName"
    }
    
    # Test de connexion à SQL Managed Instance
    Write-Log "Test de connexion à SQL Managed Instance..."
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
    
    try {
        $testQuery = "SELECT DB_NAME() AS CurrentDatabase, CURRENT_USER AS CurrentUser, @@VERSION AS SqlVersion;"
        $queryResult = Invoke-Sqlcmd -ServerInstance $fullServerName `
                                    -Database $AzureSqlDatabase `
                                    -AccessToken $accessToken `
                                    -Query $testQuery `
                                    -ErrorAction Stop
        
        Write-Log "✓ Connexion réussie à SQL MI : $($queryResult.CurrentDatabase)"
        Write-Log "✓ Utilisateur connecté : $($queryResult.CurrentUser)"
        Write-Log "✓ Version SQL : $($queryResult.SqlVersion.Substring(0,50))..."
    }
    catch {
        Write-Log "✗ Échec de connexion à SQL Managed Instance : $_" -Level "ERROR"
        Write-Log "SOLUTION : Vérifiez que la Managed Identity est configurée dans SQL MI :" -Level "ERROR"
        Write-Log "  CREATE USER [nom-managed-identity] FROM EXTERNAL PROVIDER;" -Level "ERROR"
        Write-Log "  ALTER ROLE db_datareader ADD MEMBER [nom-managed-identity];" -Level "ERROR"
        Write-Log "  -- (db_datareader suffisant pour SqlPackage export)" -Level "ERROR"
        throw "Impossible de se connecter à SQL Managed Instance"
    }
    
    # Export avec SqlPackage.exe (seule méthode supportée)
    Write-Log "=== EXPORT AVEC SQLPACKAGE (BACPAC) ==="
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $bacpacFileName = "$AzureSqlDatabase-sqlmi-$timestamp.bacpac"
    
    # Création du répertoire temporaire
    $tempDir = Join-Path -Path $env:TEMP -ChildPath ([System.Guid]::NewGuid().ToString())
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    $backupPath = Join-Path -Path $tempDir -ChildPath $bacpacFileName
    
    try {
        # Export avec SqlPackage
        Export-WithSqlPackage -ServerName $fullServerName -Database $AzureSqlDatabase -AccessToken $accessToken -OutputPath $backupPath
        
        # Upload vers Azure Storage
        Write-Log "Upload du fichier BACPAC vers Azure Storage..."
        Set-AzStorageBlobContent -File $backupPath -Container $ContainerName -Blob $bacpacFileName -Context $storageContext -Force | Out-Null
        
        # Vérification du blob
        $uploadedBlob = Get-AzStorageBlob -Container $ContainerName -Blob $bacpacFileName -Context $storageContext
        $blobSize = $uploadedBlob.Length
        $archiveFileName = $bacpacFileName
        Write-Log "✓ Fichier BACPAC uploadé : $(Format-FileSize $blobSize)"
        
    }
    finally {
        # Nettoyage du répertoire temporaire
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Génération d'un lien SAS pour téléchargement (valide 7 jours)
    $sasToken = New-AzStorageBlobSASToken -Container $ContainerName -Blob $archiveFileName -Permission "r" -ExpiryTime (Get-Date).AddDays(7) -Context $storageContext -FullUri
    
    # Résultat final
    $result = @{
        Status = "Success"
        Message = "Archivage SQL Managed Instance terminé avec succès"
        Method = "SqlPackage"
        Database = $AzureSqlDatabase
        Server = $SqlServerName
        BackupFile = $archiveFileName
        SasUri = $sasToken
        Size = Format-FileSize $blobSize
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        StorageAccount = $StorageAccountName
        Container = $ContainerName
        FileType = "BACPAC"
    }
    
    Write-Log "=== ARCHIVAGE SQL MANAGED INSTANCE TERMINÉ ==="
    Write-Log "Fichier d'archive : $archiveFileName"
    Write-Log "Type : BACPAC (SqlPackage.exe)"
    Write-Log "Taille : $(Format-FileSize $blobSize)"
    Write-Log "Lien SAS (valide 7 jours) : $sasToken"
    
    return $result
}
catch {
    # Gestion des erreurs
    Write-Log "ERREUR CRITIQUE : $_" -Level "ERROR"
    
    $errorResult = @{
        Status = "Failed"
        Error = $_.Exception.Message
        Method = "SqlPackage"
        Database = $AzureSqlDatabase
        Server = $SqlServerName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    return $errorResult
}
