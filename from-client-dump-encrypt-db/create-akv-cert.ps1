# Variables à définir directement
$SubscriptionId = "00000000-0000-0000-0000-000000000000"
$ResourceGroup = "your-resource-group"
$Location = "westeurope"
$KeyVaultName = "your-key-vault"
$DbName = 'YourDatabaseName'
$CertificateName = "cert-$DbName"
$CertSubject = "CN=$CertificateName"

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
