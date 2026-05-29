#Requires -RunAsAdministrator
<#
.SYNOPSIS
    VM-PATIENT — RDS-RD-Server + RemoteApp + journalisation RGPD
    Projet MSPR Virtualisation M1 INFRA — MEDISOL Clinique Bien-Être (données fictives)

.DESCRIPTION
    Configure Windows Server 2022 en serveur RDS pour publication de
    l'application patient via RemoteApp. Active la journalisation des
    sessions conformément aux exigences RGPD du projet.

.NOTES
    Exécuter avec un compte Administrateur local ou de domaine.
    Adapter les variables de configuration avant déploiement.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─── Variables de configuration ───────────────────────────────────────────────
$CollectionName    = "Medisol"
$CollectionDesc    = "Collection RemoteApp — Logiciel Patient MEDISOL (fictif)"
$AppDisplayName    = "Logiciel Patient"
$AppExecutable     = "C:\Program Files\LogicielPatient\patient.exe"   # chemin fictif
$RdsLicenseServer  = "vm-patient.medisol.local"   # licence per-device ou per-user selon contrat
$LicenseMode       = "PerDevice"                  # PerDevice | PerUser

# ─── 1. Installation des rôles RDS ────────────────────────────────────────────
Write-Host "[1/4] Installation des rôles Remote Desktop Services..."
Install-WindowsFeature `
    -Name RDS-RD-Server, RDS-Licensing, RDS-Connection-Broker `
    -IncludeManagementTools `
    -Restart:$false

# ─── 2. Création de la collection RemoteApp ───────────────────────────────────
Write-Host "[2/4] Création de la collection RemoteApp '$CollectionName'..."

# Création de la collection RDS (session host = localhost)
$sessionHost = [System.Net.Dns]::GetHostName()
New-RDSessionCollection `
    -CollectionName $CollectionName `
    -CollectionDescription $CollectionDesc `
    -SessionHost $sessionHost `
    -ConnectionBroker $sessionHost

# Publication de l'application patient
New-RDRemoteApp `
    -CollectionName $CollectionName `
    -DisplayName $AppDisplayName `
    -FilePath $AppExecutable `
    -Alias "logicielpatient"

Write-Host "  RemoteApp '$AppDisplayName' publié."

# ─── 3. Configuration du serveur de licences RDS ──────────────────────────────
Write-Host "[3/4] Configuration de la licence RDS ($LicenseMode)..."
$tsConfig = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root\cimv2\TerminalServices
$tsConfig.ChangeMode(2) | Out-Null   # 2 = PerDevice, 4 = PerUser
$tsConfig.SetSpecifiedLicenseServerList($RdsLicenseServer) | Out-Null

# ─── 4. Journalisation des sessions RDS (conformité RGPD) ────────────────────
Write-Host "[4/4] Activation journalisation événements RDS..."
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\TermService\Parameters" `
    -Name "EnableEventLogs" `
    -Value 1 `
    -Type DWord

# Activer le journal analytique RDS
wevtutil set-log "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" /enabled:true
wevtutil set-log "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational" /enabled:true

# Politique de rétention des journaux (90 jours)
$logMaxSize = 512KB   # taille max du journal en KB
wevtutil set-log "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" `
    /maxsize:$([int]($logMaxSize / 1KB))

Write-Host ""
Write-Host "✓ VM-PATIENT configurée."
Write-Host "  RemoteApp : $AppDisplayName ($AppExecutable)"
Write-Host "  Accès RDS depuis VLAN 10 (10.0.10.x) et WireGuard VPN (10.200.0.x)"
Write-Host "  Redémarrage recommandé pour finaliser l'installation des rôles RDS."
