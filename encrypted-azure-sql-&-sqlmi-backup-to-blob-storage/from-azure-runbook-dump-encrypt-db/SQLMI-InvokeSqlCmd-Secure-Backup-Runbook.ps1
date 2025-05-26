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
    [string]$KeyVaultName = "your-key-vault-name",
    [string]$SqlServerName = "your-sql-server-name",                     # Server name without suffix
    [string]$AzureSqlDatabase = "your-sql-database-name",
    [string]$StorageAccountName = "your-storage-account-name",
    [string]$StorageAccountRG = "your-resource-group",
    [string]$ContainerName = "your-container-name",
    [string]$CertificateName = "your-certificate-name"
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
    $access_token = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
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
        
        Write-Log "Initiating export to $backupPath"
        
        # Construct full server name if needed
        if (-not $SqlServerName.Contains('.database.windows.net')) {
            $fullServerName = "$SqlServerName.database.windows.net"
        } else {
            $fullServerName = $SqlServerName
        }
        
        Write-Log "Target server: $fullServerName"
        Write-Log "Target database: $AzureSqlDatabase"
        
        # Step 1: Test connection with Invoke-Sqlcmd
        Write-Log "Step 1: Testing connection to database with managed identity..."
        try {
            $testQuery = "SELECT DB_NAME() AS CurrentDatabase, CURRENT_USER AS CurrentUser, SYSTEM_USER AS SystemUser;"
            
            $queryResult = Invoke-Sqlcmd -ServerInstance $fullServerName `
                                       -Database $AzureSqlDatabase `
                                       -AccessToken $access_token `
                                       -Query $testQuery `
                                       -ErrorAction Stop
            
            Write-Log "✓ Successfully connected to database: $($queryResult.CurrentDatabase)"
            Write-Log "✓ Connected as user: $($queryResult.CurrentUser)"
            Write-Log "✓ System user: $($queryResult.SystemUser)"
        }
        catch {
            Write-Log "✗ Failed to connect to SQL Database: $_" -Level "ERROR"
            Write-Log "SOLUTION: You need to add the managed identity as a user in the database:" -Level "ERROR"
            Write-Log "Run this command as admin in your database:" -Level "ERROR"
            Write-Log "CREATE USER [$($context.Account.Id)] FROM EXTERNAL PROVIDER;" -Level "ERROR"
            Write-Log "ALTER ROLE db_owner ADD MEMBER [$($context.Account.Id)];" -Level "ERROR"
            throw "Managed identity not configured in database. See logs for SQL commands to run."
        }
        
        # Step 2: Backup database to storage account using T-SQL (SQL Managed Instance)
        Write-Log "Step 2: Backing up database to storage account using T-SQL..."
        
        # Create the backup file name and URL (.bak for SQL Managed Instance)
        $backupFileName = "$AzureSqlDatabase-$timestamp.bak"
        $backupUrl = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$backupFileName"
        $credentialName = "https://$StorageAccountName.blob.core.windows.net/$ContainerName"
        
        Write-Log "Backup URL: $backupUrl"
        Write-Log "Credential name: $credentialName"
        
        try {
            # Single T-SQL block to create credential and backup database
            Write-Log "Executing database backup with T-SQL..."
            
            $backupQuery = @"
-- Step 1: Create CREDENTIAL if it doesn't exist (SQL Managed Instance supports server-scoped credentials)
IF NOT EXISTS (SELECT * FROM sys.credentials WHERE name = '$credentialName')
BEGIN
    CREATE CREDENTIAL [$credentialName]
    WITH IDENTITY = 'Managed Identity';
    PRINT 'CREDENTIAL créé avec succès.';
END
ELSE
BEGIN
    PRINT 'Le CREDENTIAL existe déjà.';
END

-- Step 2: Backup database to Azure Blob Storage
PRINT 'Starting backup to: $backupUrl';

BACKUP DATABASE [$AzureSqlDatabase]
TO URL = '$backupUrl'
WITH FORMAT, INIT, COMPRESSION;

PRINT 'Backup completed successfully.';
"@
            
            Write-Log "Executing T-SQL backup command..."
            $backupResult = Invoke-Sqlcmd -ServerInstance $fullServerName `
                                        -Database $AzureSqlDatabase `
                                        -AccessToken $access_token `
                                        -Query $backupQuery `
                                        -QueryTimeout 3600 `
                                        -ErrorAction Stop
            
            Write-Log "✓ T-SQL backup command executed successfully"
            
            # Verify the backup file exists in storage
            Write-Log "Verifying backup file in storage..."
            $backupBlob = Get-AzStorageBlob -Container $ContainerName -Blob $backupFileName -Context $storageContext -ErrorAction SilentlyContinue
            
            if ($backupBlob) {
                $backupSize = $backupBlob.Length
                Write-Log "✓ Backup file verified in storage: $(Format-FileSize $backupSize)"
                
                # Download the backup file for encryption
                Write-Log "Downloading backup file for encryption..."
                Get-AzStorageBlobContent -Container $ContainerName -Blob $backupFileName -Destination $backupPath -Context $storageContext -Force | Out-Null
                
                if (Test-Path $backupPath) {
                    $localFileSize = (Get-Item $backupPath).Length
                    Write-Log "✓ Backup file downloaded: $(Format-FileSize $localFileSize)"
                    
                    # Clean up the backup blob from storage (we'll upload the encrypted version)
                    Remove-AzStorageBlob -Container $ContainerName -Blob $backupFileName -Context $storageContext -Force
                    Write-Log "✓ Original backup blob cleaned up from storage"
                } else {
                    throw "Failed to download backup file for encryption"
                }
            } else {
                throw "Backup file not found in storage account"
            }
        }
        catch {
            Write-Log "T-SQL backup operation failed: $_" -Level "ERROR"
            
            # Check if it's a permission issue
            if ($_.Exception.Message -like "*permission*" -or $_.Exception.Message -like "*access*") {
                Write-Log "SOLUTION: Ensure the managed identity has Storage Blob Data Contributor role on the storage account" -Level "ERROR"
            }
            
            throw
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