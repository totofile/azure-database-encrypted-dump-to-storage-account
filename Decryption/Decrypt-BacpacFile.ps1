$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$TenantId = "00000000-0000-0000-0000-000000000000"
$InputFile = "C:\path\to\your-database-file-name.bacpac.encrypted"
$OutputFile = "C:\path\to\your-database-name.bacpac"
$Debug = $false
# Function to write to console with timestamp
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

# Set error action preference
$ErrorActionPreference = "Stop"
if ($Debug) {
    $VerbosePreference = "Continue"
}

Write-Log "Starting BACPAC decryption" -Color Cyan
Write-Log "Input file: $InputFile" -Color Cyan
Write-Log "Output file: $OutputFile" -Color Cyan

# Check required modules
$requiredModules = @("Az.Accounts", "Az.KeyVault")
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Log "Required module $module is not installed. Please install it using: Install-Module $module -Scope CurrentUser" -Color Red
        exit 1
    }
}

try {
    # 1. Connect to Azure
    Write-Log "Connecting to Azure (Subscription: $SubscriptionId, Tenant: $TenantId)..." -Color Cyan
    Connect-AzAccount -TenantId $TenantId -Subscription $SubscriptionId
    
    # 2. Read the encrypted file header
    Write-Log "Reading encrypted file header..." -Color Cyan
    $inputStream = [System.IO.File]::OpenRead($InputFile)
    
    # Read header (8 bytes - "AKVENC01")
    $header = New-Object byte[] 8
    $inputStream.Read($header, 0, 8) | Out-Null
    $headerString = [System.Text.Encoding]::UTF8.GetString($header)
    
    if ($headerString -ne "AKVENC01") {
        Write-Log "Invalid file format. Expected: AKVENC01, received: $headerString" -Color Red
        exit 1
    }
    Write-Log "File header: '$headerString'" -Color Green
    
    # Read certificate name
    $certNameLengthBytes = New-Object byte[] 4
    $inputStream.Read($certNameLengthBytes, 0, 4) | Out-Null
    $certNameLength = [BitConverter]::ToInt32($certNameLengthBytes, 0)
    $certNameBytes = New-Object byte[] $certNameLength
    $inputStream.Read($certNameBytes, 0, $certNameLength) | Out-Null
    $certName = [System.Text.Encoding]::UTF8.GetString($certNameBytes)
    Write-Log "Certificate name: $certName" -Color Green
    
    # Read Key Vault name
    $kvNameLengthBytes = New-Object byte[] 4
    $inputStream.Read($kvNameLengthBytes, 0, 4) | Out-Null
    $kvNameLength = [BitConverter]::ToInt32($kvNameLengthBytes, 0)
    $kvNameBytes = New-Object byte[] $kvNameLength
    $inputStream.Read($kvNameBytes, 0, $kvNameLength) | Out-Null
    $kvName = [System.Text.Encoding]::UTF8.GetString($kvNameBytes)
    Write-Log "Key Vault name: $kvName" -Color Green
    
    # Read encrypted AES key
    $encryptedKeyLengthBytes = New-Object byte[] 4
    $inputStream.Read($encryptedKeyLengthBytes, 0, 4) | Out-Null
    $encryptedKeyLength = [BitConverter]::ToInt32($encryptedKeyLengthBytes, 0)
    $encryptedAesKey = New-Object byte[] $encryptedKeyLength
    $inputStream.Read($encryptedAesKey, 0, $encryptedKeyLength) | Out-Null
    Write-Log "Encrypted AES key length: $encryptedKeyLength bytes" -Color Cyan
    
    # Read AES IV
    $aesIV = New-Object byte[] 16
    $inputStream.Read($aesIV, 0, 16) | Out-Null
    
    # Read encrypted content size
    $contentSizeBytes = New-Object byte[] 8
    $inputStream.Read($contentSizeBytes, 0, 8) | Out-Null
    $contentSize = [BitConverter]::ToInt64($contentSizeBytes, 0)
    Write-Log "Encrypted content size: $contentSize bytes" -Color Cyan
    
    # Read encrypted content
    $encryptedContent = New-Object byte[] $contentSize
    $inputStream.Read($encryptedContent, 0, $contentSize) | Out-Null
    $inputStream.Close()
    
    # 3. Get the key from Key Vault and decrypt the AES key
    Write-Log "Retrieving key from Key Vault..." -Color Cyan
    
    # First try direct access to the key
    try {
        $key = Get-AzKeyVaultKey -VaultName $kvName -Name $certName
        Write-Log "Key found, attempting to decrypt AES key..." -Color Green
        
        # THIS IS THE CRITICAL PART THAT WAS FAILING - Using proper PowerShell syntax for ByteArrayValue
        $rawParameters = @{
            VaultName = $kvName
            KeyName = $certName
            Algorithm = "RSA-OAEP-256"
            Operation = "Decrypt"
            # Explicitly pass as byte array with proper parameter
            ByteArrayValue = $encryptedAesKey
        }
        
        Write-Log "Executing key operation with parameters:" -Color Cyan
        $rawParameters.Keys | ForEach-Object { 
            if ($_ -ne "ByteArrayValue") {
                Write-Log "  - $_ = $($rawParameters[$_])" -Color Gray
            } else {
                Write-Log "  - $_ = [byte[] of length $($rawParameters[$_].Length)]" -Color Gray
            }
        }
        
        # First attempt: Using the direct cmdlet
        try {
            $result = Invoke-AzKeyVaultKeyOperation @rawParameters
            
            # Check for RawResult first (this is what the encryption script uses)
            if ($null -ne $result.RawResult -and $result.RawResult.Length -gt 0) {
                $aesKey = $result.RawResult
                Write-Log "Successfully decrypted AES key via RawResult (Length: $($aesKey.Length) bytes)" -Color Green
            }
            # Fallback to Result only if RawResult is null
            elseif ($null -ne $result.Result -and $result.Result.Length -gt 0) {
                $aesKey = $result.Result
                Write-Log "Successfully decrypted AES key via Result (Length: $($aesKey.Length) bytes)" -Color Green
            }
            else {
                # If both are null, show detailed diagnostic info and throw
                Write-Log "Both Result and RawResult are null or empty!" -Color Red
                Write-Log "Key operation returned object of type: $($result.GetType().FullName)" -Color Yellow
                Write-Log "Available properties: $($result | Get-Member -MemberType Property | ForEach-Object { $_.Name })" -Color Yellow
                
                # Try to directly decrypt with Key Vault key
                Write-Log "Trying direct key operation approach..." -Color Yellow
                $keyVaultKey = Get-AzKeyVaultKey -VaultName $kvName -Name $certName
                $keyBundle = $keyVaultKey.Key
                
                $keyOperation = $keyBundle.Decrypt(
                    "RSA-OAEP-256",
                    $encryptedAesKey
                )
                
                if ($null -ne $keyOperation -and $keyOperation.Length -gt 0) {
                    $aesKey = $keyOperation
                    Write-Log "Successfully decrypted AES key via direct key operation (Length: $($aesKey.Length) bytes)" -Color Green
                }
                else {
                    throw "Key Vault decryption returned null or empty result"
                }
            }
            
            # Validate the AES key
            if ($null -eq $aesKey -or $aesKey.Length -eq 0) {
                throw "Decrypted AES key is null or empty"
            }
            
            if ($aesKey.Length -ne 32) {
                Write-Log "WARNING: Decrypted AES key length ($($aesKey.Length)) is not 32 bytes (256 bits)" -Color Yellow
            }
        }
        catch {
            Write-Log "First attempt failed: $_" -Color Yellow
            Write-Log "Trying alternative method (matching exactly what was in the encryption script)..." -Color Yellow
            
            # Second attempt: Alternative decryption with RawResult
            $keyOperation = Invoke-AzKeyVaultKeyOperation -Operation Decrypt `
                                                       -VaultName $kvName `
                                                       -KeyName $certName `
                                                       -Algorithm "RSA-OAEP-256" `
                                                       -ByteArrayValue $encryptedAesKey

            if ($null -eq $keyOperation -or ($null -eq $keyOperation.Result -and $null -eq $keyOperation.RawResult)) {
                throw "Key operation returned null or has no Result/RawResult property"
            }
            
            # Try both Result and RawResult properties
            if ($keyOperation.RawResult) {
                $aesKey = $keyOperation.RawResult
                Write-Log "Successfully decrypted AES key using RawResult (Length: $($aesKey.Length) bytes)" -Color Green
            } 
            elseif ($keyOperation.Result) {
                $aesKey = $keyOperation.Result
                Write-Log "Successfully decrypted AES key using Result (Length: $($aesKey.Length) bytes)" -Color Green
            }
            else {
                throw "Cannot retrieve decrypted AES key from key operation result"
            }
        }
    }
    catch {
        Write-Log "Failed to decrypt with Key Vault API: $_" -Color Red
        Write-Log "Trying to export certificate and decrypt locally..." -Color Yellow
        
        # Get the certificate
        $cert = Get-AzKeyVaultCertificate -VaultName $kvName -Name $certName
        $secret = Get-AzKeyVaultSecret -VaultName $kvName -Name $cert.Name
        
        $tempCertPath = Join-Path -Path $env:TEMP -ChildPath "cert_$(Get-Random).pfx"
        try {
            # Export certificate
            $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret.SecretValue)
            try {
                $secretText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
                $secretBytes = [System.Convert]::FromBase64String($secretText)
                [System.IO.File]::WriteAllBytes($tempCertPath, $secretBytes)
                
                # Load certificate with private key
                $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
                    $tempCertPath, "", 
                    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
                )
                
                if ($certObj.HasPrivateKey) {
                    # Try modern .NET method
                    try {
                        $rsa = $certObj.GetRSAPrivateKey()
                        $aesKey = $rsa.Decrypt($encryptedAesKey, [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
                        Write-Log "Successfully decrypted AES key using certificate" -Color Green
                    }
                    catch {
                        Write-Log "Local decryption failed: $_" -Color Red
                        exit 1
                    }
                }
                else {
                    Write-Log "Certificate does not contain a private key" -Color Red
                    exit 1
                }
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
            }
        }
        finally {
            if (Test-Path $tempCertPath) { 
                Remove-Item $tempCertPath -Force 
            }
        }
    }
    
    # 4. Decrypt the file content using the AES key
    Write-Log "Decrypting file content with AES..." -Color Cyan
    
    try {
        $aes = [System.Security.Cryptography.Aes]::Create()
        $aes.Key = $aesKey
        $aes.IV = $aesIV
        $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        
        $decryptor = $aes.CreateDecryptor()
        $outputFileStream = [System.IO.File]::Create($OutputFile)
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream(
            $outputFileStream, 
            $decryptor, 
            [System.Security.Cryptography.CryptoStreamMode]::Write
        )
        
        Write-Log "Writing decrypted data to $OutputFile..." -Color Cyan
        $cryptoStream.Write($encryptedContent, 0, $encryptedContent.Length)
        $cryptoStream.FlushFinalBlock()
        
        $cryptoStream.Close()
        $outputFileStream.Close()
        $aes.Dispose()
        
        # Verify output file
        $fileInfo = Get-Item -Path $OutputFile
        Write-Log "Decryption complete! Output file: $OutputFile (Size: $($fileInfo.Length) bytes)" -Color Green
    }
    catch {
        Write-Log "Failed to decrypt file content: $_" -Color Red
        exit 1
    }
}
catch {
    Write-Log "ERROR: $_" -Color Red
    exit 1
}
