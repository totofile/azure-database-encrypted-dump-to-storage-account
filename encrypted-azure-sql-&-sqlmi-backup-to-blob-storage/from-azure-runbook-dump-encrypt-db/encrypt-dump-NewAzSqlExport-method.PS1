<#
.SYNOPSIS
    Runbook for exporting and encrypting Azure SQL Database
.DESCRIPTION
    This runbook exports an Azure SQL Database to BACPAC format, encrypts it with a Key Vault certificate,
    and stores the result in Azure Blob Storage.
.NOTES
    Author: totofile
    Date: 2025-05-26
    PowerShell: 7.2
#>

# Runbook parameters
param(
    [string]$SubscriptionId = "00000000-0000-0000-0000-000000000000",
    [string]$ResourceGroup = "your-resource-group",
    [string]$KeyVaultName = "your-key-vault",
    [string]$SqlServerName = "your-server-name",                     # Server name without suffix
    [string]$AzureSqlDatabase = "your-database-name",
    [string]$StorageAccountName = "yourstorageaccount",
    [string]$StorageAccountRG = "your-storage-resource-group",
    [string]$ContainerName = "your-container-name",
    [string]$CertificateName = "cert-YourDatabaseName",
    [string]$AdminLogin = "user@example.com", # Use a Microsoft Entra ID account
    [string]$AdminPassword = "YourSecurePassword"              # Microsoft Entra ID account password
)

# Minimal configuration for runbooks
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue" # Improves performance in Automation

# Simplified logging function
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

# RUNBOOK START
Write-Log "Starting runbook for database $AzureSqlDatabase"

try {
    # Connect with managed identity
    Write-Log "Connecting to Azure..."
    Connect-AzAccount -Identity
    
    # Verify context
    $context = Get-AzContext
    Write-Log "Connected account: $($context.Account.Id)"
    
    # Select subscription
    Select-AzSubscription -SubscriptionId $SubscriptionId
    Write-Log "Subscription: $SubscriptionId"
    
    # Access Key Vault and certificate
    Write-Log "Verifying certificate $CertificateName in $KeyVaultName"
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $ResourceGroup
    $certInKv = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
    
    # Access storage
    Write-Log "Preparing storage $StorageAccountName"
    $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountRG -Name $StorageAccountName
    $storageContext = $storageAccount.Context
    $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $StorageAccountRG -Name $StorageAccountName)[0].Value
    
    # Prepare container
    $container = Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue
    if (-not $container) {
        Write-Log "Creating container $ContainerName"
        New-AzStorageContainer -Name $ContainerName -Context $storageContext -Permission Off
    }
    
    # Create temporary directory
    $tempDir = Join-Path -Path $env:TEMP -ChildPath ([System.Guid]::NewGuid().ToString())
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    
    try {
        # Prepare export
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $bacpacFileName = "$AzureSqlDatabase-$timestamp.bacpac"
        $backupPath = Join-Path -Path $tempDir -ChildPath $bacpacFileName
        $tempBacpacBlobName = "temp-$bacpacFileName"
        $blobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$tempBacpacBlobName"
        
        Write-Log "Initiating export to $blobUri"
        
        # Prepare Microsoft Entra ID credentials
        Write-Log "Configuring Microsoft Entra ID authentication"
        $securePassword = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
        
        # Launch export with Microsoft Entra ID
        $exportParams = @{
            ResourceGroupName = $ResourceGroup
            ServerName = $SqlServerName
            DatabaseName = $AzureSqlDatabase
            StorageKeyType = "StorageAccessKey"
            StorageKey = $storageKey
            StorageUri = $blobUri
            AdministratorLogin = $AdminLogin           # Must be a valid Microsoft Entra ID account
            AdministratorLoginPassword = $securePassword
            AuthenticationType = "ADPassword"          # Uses Microsoft Entra ID authentication
        }
        
        Write-Log "Executing SQL export with Microsoft Entra ID authentication..."
        Write-Log "Microsoft Entra account used: $AdminLogin"
        $exportOperation = New-AzSqlDatabaseExport @exportParams
        $operationStatus = $exportOperation.OperationStatusLink
        
        # Wait for export to complete
        Write-Log "Export started, waiting for completion..."
        $status = $null
        $exportCompleted = $false
        
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 30
            $status = Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $operationStatus
            
            if ($i % 2 -eq 0) {
                Write-Log "Export status: $($status.Status)"
            }
            
            if ($status.Status -eq "Succeeded") {
                $exportCompleted = $true
                Write-Log "Export successful!"
                break
            }
            elseif ($status.Status -eq "Failed") {
                throw "Export failed: $($status.StatusMessage)"
            }
        }
        
        if (-not $exportCompleted) {
            throw "Export was not completed within the time limit"
        }
        
        # Download BACPAC for encryption
        Write-Log "Downloading BACPAC for encryption..."
        Get-AzStorageBlobContent -Container $ContainerName -Blob $tempBacpacBlobName -Destination $backupPath -Context $storageContext -Force | Out-Null
        
        # Verify file
        if (Test-Path $backupPath) {
            $fileSize = (Get-Item $backupPath).Length
            Write-Log "BACPAC downloaded: $(Format-FileSize $fileSize)"
            
            # Remove temporary blob
            Remove-AzStorageBlob -Container $ContainerName -Blob $tempBacpacBlobName -Context $storageContext -Force
        } else {
            throw "The BACPAC file could not be downloaded"
        }
        
        # Encrypt the BACPAC
        Write-Log "Starting encryption"
        
        # Get certificate key
        $certSecret = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName
        $keyName = $certSecret.KeyId -replace '.*/keys/', '' -replace '/.*$', ''
        $keyVaultKey = Get-AzKeyVaultKey -VaultName $KeyVaultName -Name $keyName
        
        # Encrypted file
        $encryptedPath = "$backupPath.encrypted"
        
        # Generate encryption keys
        $aesKey = New-Object byte[] 32
        $aesIV = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($aesKey)
        $rng.GetBytes($aesIV)
        
        # Encrypt AES key with Key Vault
        Write-Log "Encrypting AES key with Key Vault"
        $keyOperationResult = Invoke-AzKeyVaultKeyOperation -Operation Encrypt -VaultName $KeyVaultName -KeyName $keyName -Algorithm "RSA-OAEP-256" -ByteArrayValue $aesKey
        $encryptedAesKey = $keyOperationResult.RawResult
        
        # Create encrypted file
        Write-Log "Creating encrypted file"
        $encryptedFileStream = [System.IO.File]::Create($encryptedPath)
        
        try {
            # Header
            $encryptedFileStream.Write([System.Text.Encoding]::UTF8.GetBytes("AKVENC01"), 0, 8)
            
            # Certificate
            $certNameBytes = [System.Text.Encoding]::UTF8.GetBytes($CertificateName)
            $encryptedFileStream.Write([BitConverter]::GetBytes($certNameBytes.Length), 0, 4)
            $encryptedFileStream.Write($certNameBytes, 0, $certNameBytes.Length)
            
            # Key Vault
            $kvNameBytes = [System.Text.Encoding]::UTF8.GetBytes($KeyVaultName)
            $encryptedFileStream.Write([BitConverter]::GetBytes($kvNameBytes.Length), 0, 4)
            $encryptedFileStream.Write($kvNameBytes, 0, $kvNameBytes.Length)
            
            # Encrypted AES key
            $encryptedFileStream.Write([BitConverter]::GetBytes($encryptedAesKey.Length), 0, 4)
            $encryptedFileStream.Write($encryptedAesKey, 0, $encryptedAesKey.Length)
            
            # AES IV
            $encryptedFileStream.Write($aesIV, 0, 16)
            
            # Encrypt content
            Write-Log "Encrypting content"
            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.Key = $aesKey
            $aes.IV = $aesIV
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            
            $encryptor = $aes.CreateEncryptor()
            $memStream = New-Object System.IO.MemoryStream
            $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
            
            # Read and encrypt in blocks
            $bufferSize = 4MB
            $buffer = New-Object byte[] $bufferSize
            $sourceFileStream = [System.IO.File]::OpenRead($backupPath)
            $totalRead = 0
            $fileSize = (Get-Item $backupPath).Length
            
            # Process in blocks
            while (($bytesRead = $sourceFileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $cryptoStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead
                
                if ($totalRead % (20 * $bufferSize) -eq 0) {
                    $percent = [math]::Round(($totalRead / $fileSize) * 100, 0)
                    Write-Log "Progress: $percent%"
                }
            }
            
            # Finalization
            $sourceFileStream.Close()
            $cryptoStream.FlushFinalBlock()
            
            # Write encrypted content
            $encryptedContent = $memStream.ToArray()
            $encryptedFileStream.Write([BitConverter]::GetBytes([Int64]$encryptedContent.Length), 0, 8)
            $encryptedFileStream.Write($encryptedContent, 0, $encryptedContent.Length)
            
            Write-Log "Encrypted file created: $(Format-FileSize $encryptedContent.Length)"
        }
        finally {
            # Close streams
            if ($encryptedFileStream) { $encryptedFileStream.Dispose() }
            if ($cryptoStream) { $cryptoStream.Dispose() }
            if ($memStream) { $memStream.Dispose() }
            if ($sourceFileStream -and -not $sourceFileStream.IsClosed) { $sourceFileStream.Dispose() }
            if ($aes) { $aes.Dispose() }
        }
        
        # Upload encrypted file to Blob Storage
        Write-Log "Uploading encrypted file to Azure Storage"
        $encryptedBlobName = "$AzureSqlDatabase-$timestamp.bacpac.encrypted"
        Set-AzStorageBlobContent -File $encryptedPath -Container $ContainerName -Blob $encryptedBlobName -Context $storageContext -Force | Out-Null
        
        # Generate SAS link
        $sasToken = New-AzStorageBlobSASToken -Container $ContainerName -Blob $encryptedBlobName -Permission "r" -ExpiryTime (Get-Date).AddDays(7) -Context $storageContext -FullUri
        
        # Final result
        $result = @{
            Status = "Success"
            Message = "Export and encryption successful"
            Database = $AzureSqlDatabase
            Server = $SqlServerName
            BackupFile = $encryptedBlobName
            SasUri = $sasToken
            Size = Format-FileSize (Get-Item $encryptedPath).Length
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        Write-Log "Operation completed successfully!"
        return $result
    }
    finally {
        # Cleanup
        Write-Log "Cleaning up temporary files"
        if (Test-Path -Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    # Error handling
    Write-Log "ERROR: $_" -Level "ERROR"
    return @{
        Status = "Failed"
        Error = $_.Exception.Message
        Database = $AzureSqlDatabase
        Server = $SqlServerName
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}