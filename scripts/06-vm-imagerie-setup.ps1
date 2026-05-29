#Requires -RunAsAdministrator
<#
.SYNOPSIS
    VM-IMAGERIE — File-Services + SMB chiffré + BitLocker
    Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)

.DESCRIPTION
    Configure Windows Server 2022 en serveur de fichiers pour le stockage
    de l'imagerie médicale légère. Active le chiffrement SMB 3.x,
    les ACL de partage, et BitLocker sur le volume de données.

.NOTES
    Exécuter avec un compte Administrateur local ou de domaine.
    Adapter les variables de configuration avant déploiement.
    Le volume D: doit exister et contenir le dossier Imagerie avant exécution.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Variables de configuration ───────────────────────────────────────────────
$SharePath        = "D:\Imagerie"
$ShareName        = "Imagerie"
$GroupPraticiens  = "MEDISOL\Praticiens"   # groupe AD des praticiens (fictif)
$GroupAdminIT     = "MEDISOL\Admin-IT"     # groupe AD des admins IT (fictif)
$BitLockerVolume  = "D:"

# ─── 1. Installation du rôle File Services ────────────────────────────────────
Write-Host "[1/4] Installation du rôle File Services..."
Install-WindowsFeature `
    -Name File-Services, FS-FileServer `
    -IncludeManagementTools

# ─── 2. Création du dossier de stockage imagerie ──────────────────────────────
Write-Host "[2/4] Préparation du dossier $SharePath..."
if (-not (Test-Path $SharePath)) {
    New-Item -ItemType Directory -Path $SharePath | Out-Null
}

# ACL NTFS : retirer l'héritage, définir les permissions explicites
$acl = Get-Acl $SharePath
$acl.SetAccessRuleProtection($true, $false)   # désactiver héritage, ne pas copier les règles existantes

$ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $GroupAdminIT, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
)
$rulePraticiens = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $GroupPraticiens, "ReadAndExecute, Write, Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
)

$acl.AddAccessRule($ruleAdmins)
$acl.AddAccessRule($rulePraticiens)
Set-Acl -Path $SharePath -AclObject $acl
Write-Host "  ACL NTFS configurées."

# ─── 3. Création du partage SMB avec chiffrement ──────────────────────────────
Write-Host "[3/4] Création du partage SMB chiffré '$ShareName'..."
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name $ShareName -Force
}

New-SmbShare `
    -Name $ShareName `
    -Path $SharePath `
    -EncryptData $true `
    -ReadAccess $GroupPraticiens `
    -FullAccess $GroupAdminIT `
    -FolderEnumerationMode AccessBased `
    -CachingMode None

# Forcer SMB 3.x minimum (désactiver SMB 1)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Set-SmbServerConfiguration -EncryptData $true -Force
Write-Host "  Partage \\$(hostname)\$ShareName créé (SMB chiffré, SMBv1 désactivé)."

# ─── 4. Activation BitLocker sur le volume D: ─────────────────────────────────
Write-Host "[4/4] Activation BitLocker sur $BitLockerVolume (XTS-AES-256)..."

# S'assurer que la fonctionnalité BitLocker est installée
if (-not (Get-Command Enable-BitLocker -ErrorAction SilentlyContinue)) {
    Add-WindowsFeature BitLocker -IncludeAllSubFeature -IncludeManagementTools
}

# Vérifier l'état actuel
$blStatus = Get-BitLockerVolume -MountPoint $BitLockerVolume -ErrorAction SilentlyContinue
if ($blStatus -and $blStatus.ProtectionStatus -eq "On") {
    Write-Host "  BitLocker déjà actif sur $BitLockerVolume."
} else {
    $recovery = Enable-BitLocker `
        -MountPoint $BitLockerVolume `
        -EncryptionMethod XtsAes256 `
        -UsedSpaceOnly `
        -RecoveryPasswordProtector

    $key = ($recovery.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }).RecoveryPassword
    Write-Host ""
    Write-Host "  *** CONSERVER EN LIEU SÛR — Clé de récupération BitLocker $BitLockerVolume ***"
    Write-Host "  $key"
    Write-Host "  *** Stocker dans le gestionnaire de secrets hors ligne du projet ***"
}

Write-Host ""
Write-Host "✓ VM-IMAGERIE configurée."
Write-Host "  Partage : \\$(hostname)\$ShareName (SMB 3.x chiffré)"
Write-Host "  BitLocker : $BitLockerVolume chiffré XTS-AES-256"
Write-Host "  Accès : $GroupPraticiens (lecture/écriture), $GroupAdminIT (contrôle total)"
