# Variables à définir directement
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$ResourceGroup = "your-resource-group"
$Location = "westeurope"
$KeyVaultName = "your-key-vault"
$DbName = 'YourDatabaseName'
$CertificateName = "cert-$DbName"
$CertSubject = "CN=$CertificateName"

# Paramètres Azure SQL Database (hardcodés)
$SqlServerName = "your-server-name.database.windows.net"  # Remplacer par votre serveur
$AzureSqlDatabase = "your-database-name"                  # Remplacer par votre base de données

# Paramètres de stockage (hardcodés)
$StorageAccountName = "yourstorageaccount"
$StorageAccountRG = "your-storage-resource-group"
$ContainerName = "backup"
$BackupFileName = "$AzureSqlDatabase-$(Get-Date -Format 'yyyyMMdd_HHmmss').bacpac"

# Fichier log pour le suivi des opérations
$LogFile = "C:\temp\AKV_Cert_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (-not (Test-Path "C:\temp")) {
    New-Item -Path "C:\temp" -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Tee-Object -FilePath $LogFile -Append
}

Write-Log "Starting Azure Key Vault and Certificate creation process"

try {
    # Import required modules
    Import-Module Az.Accounts, Az.KeyVault -ErrorAction Stop
    Write-Log "Required modules loaded successfully"
} 
catch {
    Write-Log "ERROR: Failed to load required modules: $_"
    throw "Failed to load required Azure modules. Please run: Install-Module -Name Az.Accounts, Az.KeyVault"
}

try {
    # Connect to Azure
    Connect-AzAccount -Subscription $SubscriptionId -ErrorAction Stop
    Write-Log "Successfully connected to Azure subscription: $SubscriptionId"
}
catch {
    Write-Log "ERROR: Failed to connect to Azure: $_"
    throw "Failed to authenticate to Azure. Check credentials and subscription ID."
}

# 1. Vérifier et créer le Key Vault si nécessaire
try {
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
    
    if (-not $keyVault) {
        Write-Log "Key Vault '$KeyVaultName' n'existe pas. Création en cours..."
        $keyVault = New-AzKeyVault -Name $KeyVaultName `
                                   -ResourceGroupName $ResourceGroup `
                                   -Location $Location `
                                   -Sku Standard `
                                   -EnabledForDeployment `
                                   -EnabledForTemplateDeployment `
                                   -EnabledForDiskEncryption `
                                   -EnablePurgeProtection $true `
                                   -SoftDeleteRetentionInDays 90 `
                                   -EnableRbacAuthorization $false
        
        Write-Log "Key Vault créé avec succès: $KeyVaultName"
    } else {
        Write-Log "Key Vault '$KeyVaultName' existe déjà dans le groupe de ressources '$ResourceGroup'"
    }
    
    # Définir les permissions d'accès pour l'utilisateur actuel
    $currentAzContext = Get-AzContext
    $currentUserId = "d62c955c-24b3-4244-9439-a83c4b2d53c1" # $currentAzContext.Account.Id
    
    Set-AzKeyVaultAccessPolicy -VaultName $KeyVaultName `
                              -UserPrincipalName $currentUserId `
                              -PermissionsToCertificates Get,List,Create,Import,Update,Delete `
                              -PermissionsToSecrets Get,List,Set,Delete
    
    Write-Log "Politiques d'accès configurées pour l'utilisateur actuel: $currentUserId"
}
catch {
    Write-Log "ERROR: Échec lors de l'opération sur le Key Vault: $_"
    throw "Impossible de créer ou d'accéder au Key Vault: $_"
}

# 2. Créer un certificat qui n'expire pas dans le Key Vault
try {
    $certInKv = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName -ErrorAction SilentlyContinue
    
    if (-not $certInKv) {
        Write-Log "Création du certificat non-expirant: $CertificateName"
        
        # Durée de validité maximale (environ 1000 ans)
        $policy = New-AzKeyVaultCertificatePolicy `
                  -SecretContentType 'application/x-pkcs12' `
                  -SubjectName $CertSubject `
                  -IssuerName 'Self' `
                  -ValidityInMonths 1199 `
                  -KeyType RSA `
                  -KeySize 4096 `
                  -KeyUsage KeyEncipherment,DataEncipherment `
                  -ReuseKeyOnRenewal $true `
                  -RenewAtNumberOfDaysBeforeExpiry 9000
        # Note: By default, keys are exportable. If you want to make it non-exportable, use -KeyNotExportable
        
        $certOp = Add-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName -CertificatePolicy $policy
        Write-Log "Demande de création de certificat initiée. Attente de la finalisation..."
        
        # Attendre la création du certificat
        do {
            Start-Sleep -Seconds 3
            $certInKv = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
            Write-Log "Statut de création du certificat: $($certInKv.Status)"
        } while ($certInKv.Status -ne 'Completed' -and -not $certInKv.SecretId)
        
        Write-Log "Certificat créé avec succès: $($certInKv.Name)"
        
        # Récupérer les détails du certificat pour vérification
        $certDetails = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
        $expiryDate = $certDetails.Expires
        Write-Log "Certificat créé avec date d'expiration: $expiryDate (environ 1000 ans)"
        
        # Afficher l'empreinte du certificat pour référence
        $thumbprint = $certDetails.Thumbprint
        Write-Log "Empreinte du certificat: $thumbprint"
    }
    else {
        Write-Log "Le certificat '$CertificateName' existe déjà dans le Key Vault"
    }
    
    Write-Host "==> Key Vault: $KeyVaultName" -ForegroundColor Green
    Write-Host "==> Certificat permanent créé: $CertificateName" -ForegroundColor Green
}
catch {
    Write-Log "ERROR: Échec lors de la création du certificat: $_"
    throw "Impossible de créer le certificat: $_"
}

# 3. Configuration et connexion à Azure SQL Database
try {
    Write-Log "Configuration pour la connexion à Azure SQL Database et la sauvegarde"
    
    # Afficher les paramètres hardcodés
    Write-Log "Utilisation des paramètres hardcodés pour Azure SQL Database"
    Write-Log "Serveur SQL: $SqlServerName"
    Write-Log "Base de données: $AzureSqlDatabase"
    
    # Test de connectivité vers le serveur Azure SQL
    Write-Log "Test de connectivité vers $SqlServerName"
    $dnsLookup = Resolve-DnsName -Name $SqlServerName -ErrorAction SilentlyContinue
    if (-not $dnsLookup) {
        Write-Log "ATTENTION: Impossible de résoudre le nom du serveur $SqlServerName. Vérifiez que le nom est correct."
        Write-Host "ATTENTION: Impossible de résoudre le nom du serveur Azure SQL. Le script va continuer mais pourrait échouer." -ForegroundColor Yellow
    } else {
        Write-Log "Le serveur $SqlServerName est accessible via DNS."
    }
    
    # Importer les modules nécessaires
    Import-Module SqlServer -ErrorAction Stop
    Write-Log "Module SqlServer importé avec succès"
    
    # Connexion à Azure SQL Database avec jeton d'authentification Microsoft Entra ID
    Write-Log "Tentative de connexion à Azure SQL Database avec jeton Microsoft Entra ID..."
    
    # 1. Récupérer le jeton d'accès pour Azure SQL Database
    $currentContext = Get-AzContext
    $tenantId = $currentContext.Tenant.Id
    Write-Log "TenantID: $tenantId"
    
    # Obtenir un jeton d'accès pour Azure SQL Database
    $sqlToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
    Write-Log "Jeton d'accès Microsoft Entra ID obtenu avec succès"
    
    # 2. Exécuter une requête test pour vérifier la connexion
    Write-Log "Test de la connexion à $SqlServerName / $AzureSqlDatabase avec le jeton d'accès"
    
    $testQuery = "SELECT DB_NAME() AS CurrentDatabase, CURRENT_USER AS CurrentUser, @@VERSION AS SqlVersion;"
    
    # Utiliser directement Invoke-Sqlcmd avec le jeton d'authentification
    $queryResult = Invoke-Sqlcmd -ServerInstance $SqlServerName `
                                -Database $AzureSqlDatabase `
                                -AccessToken $sqlToken `
                                -Query $testQuery `
                                -ErrorAction Stop
    
    # Connexion réussie, afficher les détails
    $dbName = $queryResult.CurrentDatabase
    $currentUser = $queryResult.CurrentUser
    
    Write-Log "Connexion réussie à Azure SQL Database avec jeton Microsoft Entra ID"
    Write-Log "Base de données: $dbName, Utilisateur: $currentUser"
    
    Write-Host "`nConnexion réussie à Azure SQL Database avec Microsoft Entra ID!" -ForegroundColor Green
    Write-Host "Serveur: $SqlServerName" -ForegroundColor Green
    Write-Host "Base de données: $dbName" -ForegroundColor Green
    Write-Host "Utilisateur connecté: $currentUser" -ForegroundColor Green
    
    # Obtenir le certificat depuis Key Vault pour le backup chiffré
    Write-Log "Récupération du certificat depuis Key Vault"
    $certSecret = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
    
    # Exporter le certificat du Key Vault
    try {
        Write-Log "Exportation du certificat depuis Azure Key Vault"
        $certPath = Join-Path -Path $env:TEMP -ChildPath "$CertificateName.pfx"
        
        # Obtenir le secret associé au certificat
        $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $certSecret.Name
        
        # Conversion sécurisée de SecureString à bytes puis écriture dans le fichier
        $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
        try {
            $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
            $secretBytes = [System.Convert]::FromBase64String($secretValueText)
            [System.IO.File]::WriteAllBytes($certPath, $secretBytes)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
        }
        
        Write-Log "Certificat exporté temporairement: $certPath"
        
        # Effectuer l'export de la base de données avec SqlPackage.exe
        Write-Log "Export de la base de données Azure SQL"
        
        # Préparer le chemin temporaire pour le backup
        $tempDir = [System.IO.Path]::GetTempPath()
        $backupPath = Join-Path -Path $tempDir -ChildPath "$AzureSqlDatabase-$(Get-Date -Format 'yyyyMMdd_HHmmss').bacpac"
        Write-Log "Chemin temporaire pour backup: $backupPath"
        
        # Exporter la base de données avec SqlPackage.exe
        # Chercher SqlPackage.exe
        $sqlPackagePaths = @(
            "${env:ProgramFiles}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
            "${env:ProgramFiles}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
            "${env:ProgramFiles(x86)}\Microsoft SQL Server\160\DAC\bin\SqlPackage.exe",
            "${env:ProgramFiles(x86)}\Microsoft SQL Server\150\DAC\bin\SqlPackage.exe",
            "${env:ProgramFiles}\Microsoft SQL Server Management Studio 19\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
            "${env:ProgramFiles}\Microsoft SQL Server Management Studio 18\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\SqlPackage.exe",
            "$env:USERPROFILE\.azuredatastudio\extensions\microsoft.dacpac\sqlpackage.exe"
        )
        
        $sqlPackageExe = $null
        foreach ($path in $sqlPackagePaths) {
            if (Test-Path $path) {
                $sqlPackageExe = $path
                break
            }
        }
        
        if (-not $sqlPackageExe) {
            Write-Log "SqlPackage.exe non trouvé, tentative de téléchargement..."
            $sqlPackageDownloadUrl = "https://aka.ms/sqlpackage-windows"
            $sqlPackageZipPath = Join-Path -Path $tempDir -ChildPath "sqlpackage.zip"
            $sqlPackageExtractPath = Join-Path -Path $tempDir -ChildPath "sqlpackage"
            
            try {
                Invoke-WebRequest -Uri $sqlPackageDownloadUrl -OutFile $sqlPackageZipPath
                Expand-Archive -Path $sqlPackageZipPath -DestinationPath $sqlPackageExtractPath -Force
                $sqlPackageExe = Get-ChildItem -Path $sqlPackageExtractPath -Filter "sqlpackage.exe" -Recurse | Select-Object -First 1 -ExpandProperty FullName
            }
            catch {
                Write-Log "ERREUR lors du téléchargement de SqlPackage.exe: $_"
                throw "SqlPackage.exe est requis pour l'export. Veuillez l'installer manuellement."
            }
        }
        
        Write-Log "SqlPackage.exe trouvé: $sqlPackageExe"
        
        # Créer une chaîne de connexion avec le token pour SqlPackage
        $accessTokenFile = Join-Path -Path $tempDir -ChildPath "access_token.txt"
        Set-Content -Path $accessTokenFile -Value $sqlToken -NoNewline
        
        # Exécuter SqlPackage.exe pour l'export
        Write-Log "Export de la base de données avec SqlPackage.exe"
        $sqlPackageArgs = @(
            "/Action:Export",
            "/SourceServerName:$SqlServerName",
            "/SourceDatabaseName:$AzureSqlDatabase",
            "/SourceTrustServerCertificate:True",
            "/SourceTimeout:3600",
            "/TargetFile:$backupPath",
            "/AccessToken:$sqlToken"
        )
        
        try {
            $process = Start-Process -FilePath $sqlPackageExe -ArgumentList $sqlPackageArgs -NoNewWindow -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "SqlPackage.exe a retourné un code d'erreur: $($process.ExitCode)"
            }
            
            Write-Log "Export réussi: $backupPath"
        }
        catch {
            Write-Log "ERREUR lors de l'export: $_"
            throw "Échec de l'export de la base de données: $_"
        }
        finally {
            # Supprimer le fichier token temporaire
            if (Test-Path $accessTokenFile) {
                Remove-Item -Path $accessTokenFile -Force
            }
        }
        
        # Chiffrer le fichier BACPAC avec PowerShell et le certificat
        if (Test-Path $backupPath) {
            Write-Log "Chiffrement du fichier BACPAC avec PowerShell"
            
            # Chemin pour le fichier BACPAC chiffré
            $encryptedPath = "$backupPath.encrypted"
            
            # Importer le certificat pour le chiffrement - la méthode GetRSAPublicKey() n'existe pas dans cette version de .NET
            # On va utiliser directement la clé du Key Vault associée au certificat
            
            Write-Log "Utilisation de la clé associée au certificat pour le chiffrement"
            
            # Obtenir la clé associée au certificat dans Key Vault
            $keyName = $certSecret.KeyId -replace '.*/keys/', '' -replace '/.*$', ''
            Write-Log "Récupération de la clé associée au certificat: $keyName"
            $keyVaultKey = Get-AzKeyVaultKey -VaultName $KeyVaultName -Name $keyName
            
            if (-not $keyVaultKey) {
                throw "Impossible de récupérer la clé associée au certificat dans Key Vault"
            }
            
            Write-Log "Clé récupérée, préparation du chiffrement hybride du fichier BACPAC"
            
            # Générer une clé AES aléatoire pour le chiffrement symétrique du fichier
            $aesKey = New-Object byte[] 32  # AES-256
            $aesIV = New-Object byte[] 16   # IV standard pour AES
            
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($aesKey)
            $rng.GetBytes($aesIV)
            
            # Chiffrer la clé AES avec la clé du Key Vault
            Write-Log "Chiffrement de la clé AES avec la clé du Key Vault"
            
            $keyOperationResult = Invoke-AzKeyVaultKeyOperation -Operation Encrypt `
                                              -VaultName $KeyVaultName `
                                              -KeyName $keyName `
                                              -Algorithm "RSA-OAEP-256" `
                                              -ByteArrayValue $aesKey `
                                              -ErrorAction Stop
            
            if ($null -eq $keyOperationResult -or $null -eq $keyOperationResult.RawResult) {
                Write-Log "ERREUR: Échec de chiffrement de la clé AES avec Key Vault"
                throw "Le chiffrement de la clé AES a échoué"
            }
            
            $encryptedAesKey = $keyOperationResult.RawResult
            Write-Log "Clé AES chiffrée avec succès, longueur: $($encryptedAesKey.Length) bytes"
            
            # Créer le fichier chiffré
            try {
                Write-Log "Chiffrement du contenu du fichier avec AES-256"
                $encryptedPath = "$backupPath.encrypted"
                $encryptedFileStream = [System.IO.File]::Create($encryptedPath)
                
                # Écrire un en-tête simple pour identifier le fichier
                $header = [System.Text.Encoding]::UTF8.GetBytes("AKVENC01")
                $encryptedFileStream.Write($header, 0, $header.Length)
                
                # Écrire le nom du certificat
                $certNameBytes = [System.Text.Encoding]::UTF8.GetBytes($CertificateName)
                $certNameLength = [BitConverter]::GetBytes($certNameBytes.Length)
                $encryptedFileStream.Write($certNameLength, 0, 4)
                $encryptedFileStream.Write($certNameBytes, 0, $certNameBytes.Length)
                
                # Écrire le nom du Key Vault
                $kvNameBytes = [System.Text.Encoding]::UTF8.GetBytes($KeyVaultName)
                $kvNameLength = [BitConverter]::GetBytes($kvNameBytes.Length)
                $encryptedFileStream.Write($kvNameLength, 0, 4)
                $encryptedFileStream.Write($kvNameBytes, 0, $kvNameBytes.Length)
                
                # Écrire la clé AES chiffrée
                $encryptedKeyLength = [BitConverter]::GetBytes($encryptedAesKey.Length)
                $encryptedFileStream.Write($encryptedKeyLength, 0, 4)
                $encryptedFileStream.Write($encryptedAesKey, 0, $encryptedAesKey.Length)
                
                # Écrire l'IV AES
                $encryptedFileStream.Write($aesIV, 0, $aesIV.Length)
                
                # Vérifier le fichier BACPAC
                if (-not (Test-Path -Path $backupPath) -or (Get-Item -Path $backupPath).Length -eq 0) {
                    Write-Log "ERREUR: Fichier BACPAC inexistant ou vide: $backupPath"
                    throw "Le fichier BACPAC source est introuvable ou vide"
                }
                
                # Chiffrer le contenu par blocs
                Write-Log "Chiffrement du fichier BACPAC: $backupPath ($(([System.IO.FileInfo]$backupPath).Length) bytes)"
                
                $aes = [System.Security.Cryptography.Aes]::Create()
                $aes.Key = $aesKey
                $aes.IV = $aesIV
                $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
                $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
                
                $encryptor = $aes.CreateEncryptor()
                $bufferSize = 4MB
                $buffer = New-Object byte[] $bufferSize
                $memStream = New-Object System.IO.MemoryStream
                $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
                
                $sourceFileStream = [System.IO.File]::OpenRead($backupPath)
                $bytesRead = 0
                $totalBytesRead = 0
                $fileSize = (Get-Item $backupPath).Length
                
                while (($bytesRead = $sourceFileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $cryptoStream.Write($buffer, 0, $bytesRead)
                    $totalBytesRead += $bytesRead
                    $percentComplete = [math]::Round(($totalBytesRead / $fileSize) * 100, 0)
                    
                    if ($percentComplete % 10 -eq 0) {
                        Write-Progress -Activity "Chiffrement du BACPAC" -Status "$percentComplete% Complete" -PercentComplete $percentComplete
                    }
                }
                
                $sourceFileStream.Close()
                $cryptoStream.FlushFinalBlock()
                
                $encryptedContent = $memStream.ToArray()
                Write-Log "Chiffrement terminé: $($encryptedContent.Length) bytes"
                
                # Écrire la taille et le contenu chiffré
                $contentSize = [BitConverter]::GetBytes([Int64]$encryptedContent.Length)
                $encryptedFileStream.Write($contentSize, 0, 8)
                $encryptedFileStream.Write($encryptedContent, 0, $encryptedContent.Length)
                
                # Fermer les streams
                $cryptoStream.Close()
                $memStream.Close()
                $encryptedFileStream.Close()
                $aes.Dispose()
                $encryptor.Dispose()
                
                Write-Log "Fichier chiffré créé: $encryptedPath"
            }
            catch {
                Write-Log "ERREUR lors du chiffrement: $_"
                throw $_
            }
            
            # Télécharger vers Azure Storage
            Write-Log "Téléchargement vers Azure Storage"
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName
            $storageContext = $storageAccount.Context
            
            $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
            if (-not $container) {
                Write-Log "Création du container $ContainerName"
                New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off
            }
            
            $encryptedBlobName = [System.IO.Path]::GetFileName($encryptedPath)
            Set-AzStorageBlobContent -File $encryptedPath -Container $ContainerName -Blob $encryptedBlobName -Context $storageContext -Force
            
            $blob = Get-AzStorageBlob -Container $ContainerName -Blob $encryptedBlobName -Context $storageContext
            $blobUrl = $blob.ICloudBlob.Uri.AbsoluteUri
            
            Write-Log "Backup chiffré téléchargé: $blobUrl"
            Write-Host "Backup chiffré téléchargé avec succès: $blobUrl" -ForegroundColor Green
            Write-Host "Voir README_DECRYPT.md pour les instructions de déchiffrement" -ForegroundColor Green
            
            # Nettoyage
            Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $encryptedPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $certPath -Force -ErrorAction SilentlyContinue
          }
          else {
              Write-Log "ERREUR: Le fichier BACPAC n'a pas été créé"
              throw "Échec de l'export de la base de données"
          }
        }
        catch {
            Write-Log "ERREUR: $_"
            throw "Échec lors du chiffrement ou de l'upload du backup: $_"
        }
        
        Write-Host "`n==> Opération terminée avec succès. Consultez le fichier log pour les détails: $LogFile" -ForegroundColor Green
}
catch {
    Write-Log "ERROR: Échec lors du backup de la base Azure SQL: $_"
    throw "Impossible de sauvegarder la base Azure SQL: $_"
}

Write-Log "Opération terminée avec succès."