<#
.SYNOPSIS
    GRC Hyper-V Lab – Active Directory Population Script
    Creates a realistic corporate AD environment for audit script development and testing.

.DESCRIPTION
    Populates the domain corp.grclab.local with:
      - Full OU hierarchy (corporate + department structure)
      - ~200 user accounts across departments (with realistic attributes)
      - 50+ security and distribution groups (nested where appropriate)
      - 30+ computer objects across workstations, servers, and laptops
      - 10+ service accounts (some with intentional audit findings)
      - Fine-grained password policies (PSOs)
      - 12 GPOs linked to appropriate OUs
      - Intentional GRC findings seeded throughout (see MISCONFIGURATIONS.md)

.PARAMETER DomainName
    FQDN of the domain. Default: corp.grclab.local

.PARAMETER DomainNetBIOS
    NetBIOS name. Default: GRCLAB

.PARAMETER DefaultPassword
    Default password for all created accounts. Must meet domain policy.

.PARAMETER SeedMisconfigurations
    If specified, applies intentional GRC audit findings on top of the base population.

.EXAMPLE
    # Run on DC-PRIMARY after AD DS is promoted
    .\Invoke-ADLabPopulate.ps1 -SeedMisconfigurations

.NOTES
    Run as Domain Administrator on DC-PRIMARY (10.10.10.10)
    Requires: ActiveDirectory PowerShell module (RSAT or installed via AD DS role)
    Estimated runtime: 8-15 minutes
#>

[CmdletBinding()]
param(
    [string]$DomainName       = "corp.grclab.local",
    [string]$DomainNetBIOS    = "GRCLAB",
    [string]$DefaultPassword  = "LabP@ssw0rd2024!",
    [switch]$SeedMisconfigurations,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$WarningPreference     = "Continue"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step   { param($msg) Write-Host "`n[*] $msg" -ForegroundColor Cyan   }
function Write-OK     { param($msg) Write-Host "    [+] $msg" -ForegroundColor Green }
function Write-Skip   { param($msg) Write-Host "    [-] $msg (already exists)" -ForegroundColor DarkGray }
function Write-Finding{ param($msg) Write-Host "    [!] FINDING SEEDED: $msg" -ForegroundColor Yellow }
function Write-Err    { param($msg) Write-Host "    [X] ERROR: $msg" -ForegroundColor Red }

function ConvertTo-SecureStringHelper { param($plain)
    ConvertTo-SecureString $plain -AsPlainText -Force
}

$DomainDN   = "DC=" + ($DomainName -replace "\.", ",DC=")
$SecurePwd  = ConvertTo-SecureStringHelper $DefaultPassword

function New-OUSafe {
    param([string]$Name, [string]$Path, [string]$Description = "")
    try {
        Get-ADOrganizationalUnit -Filter "Name -eq '$Name'" -SearchBase $Path -SearchScope OneLevel -ErrorAction Stop | Out-Null
        Write-Skip "OU: $Name"
    } catch {
        New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $false
        Write-OK "OU: $Name"
    }
}

function New-UserSafe {
    param(
        [string]$SamAccountName,
        [string]$GivenName,
        [string]$Surname,
        [string]$Department,
        [string]$Title,
        [string]$Path,
        [string]$Description      = "",
        [string]$OfficePhone      = "",
        [string]$Manager          = "",
        [bool]$Enabled            = $true,
        [bool]$PwdNeverExpires    = $false,
        [bool]$MustChangePwd      = $false,
        [bool]$PwdCantChange      = $false,
        [string]$EmployeeID       = "",
        [string]$Company          = "GRCLAB Corp",
        [string]$Office           = ""
    )
    try {
        Get-ADUser -Identity $SamAccountName -ErrorAction Stop | Out-Null
        Write-Skip "User: $SamAccountName"
    } catch {
        $params = @{
            SamAccountName        = $SamAccountName
            GivenName             = $GivenName
            Surname               = $Surname
            Name                  = "$GivenName $Surname"
            DisplayName           = "$GivenName $Surname"
            UserPrincipalName     = "$SamAccountName@$DomainName"
            EmailAddress          = "$SamAccountName@grclab.local"
            Department            = $Department
            Title                 = $Title
            Description           = $Description
            Path                  = $Path
            AccountPassword       = $SecurePwd
            Enabled               = $Enabled
            PasswordNeverExpires  = $PwdNeverExpires
            ChangePasswordAtLogon = $MustChangePwd
            CannotChangePassword  = $PwdCantChange
        }
        if ($OfficePhone) { $params['OfficePhone'] = $OfficePhone }
        if ($Office)      { $params['Office']      = $Office }
        if ($Company)     { $params['Company']     = $Company }
        if ($EmployeeID)  { $params['EmployeeID']  = $EmployeeID }

        New-ADUser @params
        Write-OK "User: $SamAccountName ($Title, $Department)"
    }
}

function New-GroupSafe {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Description = "",
        [string]$GroupScope  = "Global",
        [string]$GroupCategory = "Security"
    )
    try {
        Get-ADGroup -Identity $Name -ErrorAction Stop | Out-Null
        Write-Skip "Group: $Name"
    } catch {
        New-ADGroup -Name $Name -SamAccountName $Name -GroupScope $GroupScope `
            -GroupCategory $GroupCategory -Path $Path -Description $Description
        Write-OK "Group: $Name ($GroupScope $GroupCategory)"
    }
}

function Add-GroupMemberSafe {
    param([string]$Group, [string[]]$Members)
    foreach ($m in $Members) {
        try {
            Add-ADGroupMember -Identity $Group -Members $m -ErrorAction Stop
        } catch {
            # silently skip if already member or object not found
        }
    }
}

function New-ComputerSafe {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Description = "",
        [string]$Location    = "",
        [string]$OS          = "Windows 10 Enterprise",
        [string]$OSVersion   = "10.0 (19045)"
    )
    try {
        Get-ADComputer -Identity $Name -ErrorAction Stop | Out-Null
        Write-Skip "Computer: $Name"
    } catch {
        New-ADComputer -Name $Name -Path $Path -Description $Description `
            -Location $Location -OperatingSystem $OS `
            -OperatingSystemVersion $OSVersion -Enabled $true
        Write-OK "Computer: $Name"
    }
}


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 1 – OU HIERARCHY
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Building OU hierarchy..."

# Top-level corporate OUs
$ouDefs = @(
    @{ Name="Corp";           Path=$DomainDN;                          Desc="GRCLAB Corp root OU" },
    @{ Name="Tier0-Admins";   Path=$DomainDN;                          Desc="Tier 0 privileged admin accounts (PAM)" },
    @{ Name="Tier1-Servers";  Path=$DomainDN;                          Desc="Tier 1 server admin accounts" },
    @{ Name="Quarantine";     Path=$DomainDN;                          Desc="Disabled/quarantined accounts staging" }
)
foreach ($ou in $ouDefs) { New-OUSafe -Name $ou.Name -Path $ou.Path -Description $ou.Desc }

$corpOU     = "OU=Corp,$DomainDN"
$t0OU       = "OU=Tier0-Admins,$DomainDN"
$t1OU       = "OU=Tier1-Servers,$DomainDN"
$quarOU     = "OU=Quarantine,$DomainDN"

# Corp sub-OUs
$corpSubs = @("Users","Computers","Groups","ServiceAccounts","Resources","Contacts")
foreach ($s in $corpSubs) { New-OUSafe -Name $s -Path $corpOU }

$usersOU   = "OU=Users,$corpOU"
$compOU    = "OU=Computers,$corpOU"
$groupsOU  = "OU=Groups,$corpOU"
$svcOU     = "OU=ServiceAccounts,$corpOU"
$resOU     = "OU=Resources,$corpOU"

# Department OUs under Users
$departments = @(
    @{ Name="IT";                 Path=$usersOU; Desc="Information Technology" },
    @{ Name="Finance";            Path=$usersOU; Desc="Finance & Accounting" },
    @{ Name="HR";                 Path=$usersOU; Desc="Human Resources" },
    @{ Name="Legal";              Path=$usersOU; Desc="Legal & Compliance" },
    @{ Name="Operations";         Path=$usersOU; Desc="Operations" },
    @{ Name="Sales";              Path=$usersOU; Desc="Sales & Business Development" },
    @{ Name="Marketing";          Path=$usersOU; Desc="Marketing & Communications" },
    @{ Name="Engineering";        Path=$usersOU; Desc="Software Engineering & R&D" },
    @{ Name="Executives";         Path=$usersOU; Desc="C-Suite and VP-level" },
    @{ Name="Contractors";        Path=$usersOU; Desc="External contractors (limited access)" },
    @{ Name="Disabled";           Path=$usersOU; Desc="Disabled/offboarded accounts" }
)
foreach ($d in $departments) { New-OUSafe -Name $d.Name -Path $d.Path -Description $d.Desc }

# Computer sub-OUs
$compSubs = @(
    @{ Name="Desktops-Win10";    Path=$compOU; Desc="Windows 10 domain workstations" },
    @{ Name="Desktops-Win11";    Path=$compOU; Desc="Windows 11 domain workstations" },
    @{ Name="Laptops";           Path=$compOU; Desc="Domain-joined laptops" },
    @{ Name="Servers-App";       Path=$compOU; Desc="Application servers" },
    @{ Name="Servers-File";      Path=$compOU; Desc="File and print servers" },
    @{ Name="Servers-Web";       Path=$compOU; Desc="Web and IIS servers" },
    @{ Name="Kiosks";            Path=$compOU; Desc="Shared kiosk and lobby machines" }
)
foreach ($c in $compSubs) { New-OUSafe -Name $c.Name -Path $c.Path -Description $c.Desc }

# Group sub-OUs
$grpSubs = @(
    @{ Name="SecurityGroups";    Path=$groupsOU; Desc="Access control security groups" },
    @{ Name="DistributionLists"; Path=$groupsOU; Desc="Email distribution lists" },
    @{ Name="RoleGroups";        Path=$groupsOU; Desc="Role-based access groups (RBAC)" },
    @{ Name="GPO-Filter-Groups"; Path=$groupsOU; Desc="Groups used for GPO security filtering" }
)
foreach ($g in $grpSubs) { New-OUSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

$secGroupsOU  = "OU=SecurityGroups,$groupsOU"
$distGroupsOU = "OU=DistributionLists,$groupsOU"
$roleGroupsOU = "OU=RoleGroups,$groupsOU"
$gpoGroupsOU  = "OU=GPO-Filter-Groups,$groupsOU"

# Department-level paths (shorthand)
$ouIT    = "OU=IT,$usersOU"
$ouFin   = "OU=Finance,$usersOU"
$ouHR    = "OU=HR,$usersOU"
$ouLegal = "OU=Legal,$usersOU"
$ouOps   = "OU=Operations,$usersOU"
$ouSales = "OU=Sales,$usersOU"
$ouMkt   = "OU=Marketing,$usersOU"
$ouEng   = "OU=Engineering,$usersOU"
$ouExec  = "OU=Executives,$usersOU"
$ouCont  = "OU=Contractors,$usersOU"
$ouDis   = "OU=Disabled,$usersOU"

$ouDeskW10  = "OU=Desktops-Win10,$compOU"
$ouDeskW11  = "OU=Desktops-Win11,$compOU"
$ouLaptops  = "OU=Laptops,$compOU"
$ouSrvApp   = "OU=Servers-App,$compOU"
$ouSrvFile  = "OU=Servers-File,$compOU"
$ouSrvWeb   = "OU=Servers-Web,$compOU"
$ouKiosks   = "OU=Kiosks,$compOU"

Write-OK "OU hierarchy complete."

# ═════════════════════════════════════════════════════════════════════════════
# SECTION 2 – SECURITY & DISTRIBUTION GROUPS
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Creating security and distribution groups..."

# ── Privileged / Admin Groups ──────────────────────────────────────────────
$privGroups = @(
    @{ Name="GRC-Domain-Admins";         Path=$secGroupsOU; Desc="Custom Domain Admin delegation group – DO NOT add regular users" },
    @{ Name="GRC-Server-Admins";         Path=$secGroupsOU; Desc="Tier 1 server administrators" },
    @{ Name="GRC-Helpdesk";              Path=$secGroupsOU; Desc="L1/L2 helpdesk – limited AD delegation" },
    @{ Name="GRC-AD-Operators";          Path=$secGroupsOU; Desc="AD read/write for user and group management" },
    @{ Name="GRC-GPO-Admins";            Path=$secGroupsOU; Desc="Group Policy Object administrators" },
    @{ Name="GRC-Backup-Operators";      Path=$secGroupsOU; Desc="Backup and restore operators" },
    @{ Name="GRC-Network-Admins";        Path=$secGroupsOU; Desc="Network infrastructure administrators" },
    @{ Name="GRC-Security-Team";         Path=$secGroupsOU; Desc="Information Security / SOC team" },
    @{ Name="GRC-Audit-ReadOnly";        Path=$secGroupsOU; Desc="Read-only auditor access to AD – for GRC team" }
)
foreach ($g in $privGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── Department Resource Groups ─────────────────────────────────────────────
$deptGroups = @(
    @{ Name="GRP-IT-Staff";              Path=$secGroupsOU; Desc="All IT department staff" },
    @{ Name="GRP-Finance-Staff";         Path=$secGroupsOU; Desc="All Finance department staff" },
    @{ Name="GRP-HR-Staff";              Path=$secGroupsOU; Desc="All HR department staff" },
    @{ Name="GRP-Legal-Staff";           Path=$secGroupsOU; Desc="All Legal & Compliance staff" },
    @{ Name="GRP-Operations-Staff";      Path=$secGroupsOU; Desc="All Operations staff" },
    @{ Name="GRP-Sales-Staff";           Path=$secGroupsOU; Desc="All Sales staff" },
    @{ Name="GRP-Marketing-Staff";       Path=$secGroupsOU; Desc="All Marketing staff" },
    @{ Name="GRP-Engineering-Staff";     Path=$secGroupsOU; Desc="All Engineering staff" },
    @{ Name="GRP-Executives";            Path=$secGroupsOU; Desc="Executive leadership group" },
    @{ Name="GRP-All-Employees";         Path=$secGroupsOU; Desc="All active employees – company-wide" },
    @{ Name="GRP-Contractors";           Path=$secGroupsOU; Desc="External contractor accounts" }
)
foreach ($g in $deptGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── File Share Access Groups ───────────────────────────────────────────────
$shareGroups = @(
    @{ Name="FS-Finance-ReadOnly";       Path=$secGroupsOU; Desc="Read-only access to Finance file share" },
    @{ Name="FS-Finance-ReadWrite";      Path=$secGroupsOU; Desc="Read-write access to Finance file share" },
    @{ Name="FS-HR-Confidential";        Path=$secGroupsOU; Desc="HR confidential documents access" },
    @{ Name="FS-Legal-Confidential";     Path=$secGroupsOU; Desc="Legal confidential documents access" },
    @{ Name="FS-Engineering-Repos";      Path=$secGroupsOU; Desc="Engineering source and build share" },
    @{ Name="FS-Shared-General";         Path=$secGroupsOU; Desc="General company shared drive access" },
    @{ Name="FS-IT-Admin-Share";         Path=$secGroupsOU; Desc="IT admin file share (scripts, tools)" }
)
foreach ($g in $shareGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── Application Access Groups ──────────────────────────────────────────────
$appGroups = @(
    @{ Name="APP-ERP-Users";             Path=$secGroupsOU; Desc="Access to ERP system (SAP-sim)" },
    @{ Name="APP-ERP-Admins";            Path=$secGroupsOU; Desc="ERP system administrator accounts" },
    @{ Name="APP-CRM-Users";             Path=$secGroupsOU; Desc="CRM system access (Salesforce-sim)" },
    @{ Name="APP-ITSM-Users";            Path=$secGroupsOU; Desc="ITSM tool access (ServiceNow-sim)" },
    @{ Name="APP-ITSM-Admins";           Path=$secGroupsOU; Desc="ITSM admin group" },
    @{ Name="APP-VPN-Users";             Path=$secGroupsOU; Desc="VPN access – Remote work users" },
    @{ Name="APP-RDP-Servers";           Path=$secGroupsOU; Desc="Remote Desktop access to servers" },
    @{ Name="APP-SQL-ReadOnly";          Path=$secGroupsOU; Desc="SQL Server read-only access" },
    @{ Name="APP-SQL-ReadWrite";         Path=$secGroupsOU; Desc="SQL Server read-write access" },
    @{ Name="APP-SharePoint-Members";    Path=$secGroupsOU; Desc="SharePoint intranet members" },
    @{ Name="APP-SharePoint-Owners";     Path=$secGroupsOU; Desc="SharePoint site owners/admins" }
)
foreach ($g in $appGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── Role Groups (RBAC) ─────────────────────────────────────────────────────
$roleGroups = @(
    @{ Name="ROLE-Privileged-Users";     Path=$roleGroupsOU; Desc="All accounts with admin-level privileges – SOX audit scope" },
    @{ Name="ROLE-Remote-Workers";       Path=$roleGroupsOU; Desc="Users approved for remote/hybrid work" },
    @{ Name="ROLE-Exec-IT-Access";       Path=$roleGroupsOU; Desc="Executive devices with special IT policy" },
    @{ Name="ROLE-Dev-Workstations";     Path=$roleGroupsOU; Desc="Engineers with dev tools and elevated local rights" },
    @{ Name="ROLE-Finance-SOX-Scope";    Path=$roleGroupsOU; Desc="Finance users in SOX audit scope" },
    @{ Name="ROLE-HR-Sensitive-Data";    Path=$roleGroupsOU; Desc="HR users with access to PII/sensitive HR data" },
    @{ Name="ROLE-Kiosk-Users";          Path=$roleGroupsOU; Desc="Shared kiosk login accounts" }
)
foreach ($g in $roleGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── GPO Filter Groups ──────────────────────────────────────────────────────
$gpoGroups = @(
    @{ Name="GPO-Exempt-IE-Lockdown";    Path=$gpoGroupsOU; Desc="Accounts exempt from IE hardening GPO" },
    @{ Name="GPO-Exempt-USB-Block";      Path=$gpoGroupsOU; Desc="IT staff exempt from USB block policy" },
    @{ Name="GPO-Apply-DevTools";        Path=$gpoGroupsOU; Desc="Receive dev tools install GPO" },
    @{ Name="GPO-Apply-ExecProfile";     Path=$gpoGroupsOU; Desc="Receive executive desktop profile GPO" }
)
foreach ($g in $gpoGroups) { New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc }

# ── Distribution Lists ─────────────────────────────────────────────────────
$distLists = @(
    @{ Name="DL-All-Staff";              Path=$distGroupsOU; Desc="All staff email list" },
    @{ Name="DL-IT-Department";          Path=$distGroupsOU; Desc="IT department email list" },
    @{ Name="DL-Finance-Department";     Path=$distGroupsOU; Desc="Finance department email list" },
    @{ Name="DL-HR-Department";          Path=$distGroupsOU; Desc="HR department email list" },
    @{ Name="DL-Executives";             Path=$distGroupsOU; Desc="Executive email list" },
    @{ Name="DL-Security-Alerts";        Path=$distGroupsOU; Desc="Security alert notification list" },
    @{ Name="DL-Helpdesk-Queue";         Path=$distGroupsOU; Desc="Helpdesk ticket notification list" },
    @{ Name="DL-Engineering-Team";       Path=$distGroupsOU; Desc="Engineering team email list" }
)
foreach ($g in $distLists) {
    New-GroupSafe -Name $g.Name -Path $g.Path -Description $g.Desc -GroupCategory "Distribution"
}

Write-OK "Groups created."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 3 – USER ACCOUNTS
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Creating user accounts..."

# ── IT Department ──────────────────────────────────────────────────────────
$itUsers = @(
    @{ Sam="john.smith";       First="John";      Last="Smith";       Title="IT Director";               Phone="555-1001"; EmpID="E1001" },
    @{ Sam="alice.wu";         First="Alice";     Last="Wu";          Title="Senior Systems Administrator";Phone="555-1002"; EmpID="E1002" },
    @{ Sam="derek.nguyen";     First="Derek";     Last="Nguyen";      Title="Systems Administrator";      Phone="555-1003"; EmpID="E1003" },
    @{ Sam="priya.patel";      First="Priya";     Last="Patel";       Title="Cloud Infrastructure Engineer";Phone="555-1004"; EmpID="E1004" },
    @{ Sam="tom.harris";       First="Tom";       Last="Harris";      Title="Network Administrator";      Phone="555-1005"; EmpID="E1005" },
    @{ Sam="linda.chang";      First="Linda";     Last="Chang";       Title="Security Analyst";           Phone="555-1006"; EmpID="E1006" },
    @{ Sam="omar.hassan";      First="Omar";      Last="Hassan";      Title="Security Engineer";          Phone="555-1007"; EmpID="E1007" },
    @{ Sam="jessica.ford";     First="Jessica";   Last="Ford";        Title="Helpdesk Technician L2";     Phone="555-1008"; EmpID="E1008" },
    @{ Sam="kevin.moore";      First="Kevin";     Last="Moore";       Title="Helpdesk Technician L1";     Phone="555-1009"; EmpID="E1009" },
    @{ Sam="rachel.green";     First="Rachel";    Last="Green";       Title="Helpdesk Technician L1";     Phone="555-1010"; EmpID="E1010" },
    @{ Sam="ben.carter";       First="Ben";       Last="Carter";      Title="DevOps Engineer";            Phone="555-1011"; EmpID="E1011" },
    @{ Sam="nat.jones";        First="Natalie";   Last="Jones";       Title="Database Administrator";     Phone="555-1012"; EmpID="E1012" }
)
foreach ($u in $itUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "IT" -Title $u.Title -Path $ouIT `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-A"
}

# ── Finance Department ─────────────────────────────────────────────────────
$finUsers = @(
    @{ Sam="sarah.johnson";    First="Sarah";     Last="Johnson";     Title="CFO";                        Phone="555-2001"; EmpID="E2001" },
    @{ Sam="mike.brown";       First="Mike";      Last="Brown";       Title="Controller";                 Phone="555-2002"; EmpID="E2002" },
    @{ Sam="emily.davis";      First="Emily";     Last="Davis";       Title="Senior Accountant";          Phone="555-2003"; EmpID="E2003" },
    @{ Sam="carlos.rivera";    First="Carlos";    Last="Rivera";      Title="Accountant";                 Phone="555-2004"; EmpID="E2004" },
    @{ Sam="diana.clark";      First="Diana";     Last="Clark";       Title="Accounts Payable Specialist"; Phone="555-2005"; EmpID="E2005" },
    @{ Sam="frank.miller";     First="Frank";     Last="Miller";      Title="Accounts Receivable Specialist";Phone="555-2006"; EmpID="E2006" },
    @{ Sam="grace.lee";        First="Grace";     Last="Lee";         Title="Payroll Manager";            Phone="555-2007"; EmpID="E2007" },
    @{ Sam="henry.wilson";     First="Henry";     Last="Wilson";      Title="Payroll Specialist";         Phone="555-2008"; EmpID="E2008" },
    @{ Sam="irene.martin";     First="Irene";     Last="Martin";      Title="Financial Analyst";          Phone="555-2009"; EmpID="E2009" },
    @{ Sam="james.taylor";     First="James";     Last="Taylor";      Title="Budget Analyst";             Phone="555-2010"; EmpID="E2010" },
    @{ Sam="karen.white";      First="Karen";     Last="White";       Title="Treasury Analyst";           Phone="555-2011"; EmpID="E2011" },
    @{ Sam="leo.anderson";     First="Leo";       Last="Anderson";    Title="Tax Specialist";             Phone="555-2012"; EmpID="E2012" }
)
foreach ($u in $finUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Finance" -Title $u.Title -Path $ouFin `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-B"
}

# ── HR Department ──────────────────────────────────────────────────────────
$hrUsers = @(
    @{ Sam="mary.thompson";    First="Mary";      Last="Thompson";    Title="HR Director";                Phone="555-3001"; EmpID="E3001" },
    @{ Sam="paul.jackson";     First="Paul";      Last="Jackson";     Title="HR Business Partner";        Phone="555-3002"; EmpID="E3002" },
    @{ Sam="quinn.adams";      First="Quinn";     Last="Adams";       Title="Recruiter";                  Phone="555-3003"; EmpID="E3003" },
    @{ Sam="rosa.sanchez";     First="Rosa";      Last="Sanchez";     Title="Recruiter";                  Phone="555-3004"; EmpID="E3004" },
    @{ Sam="steve.hall";       First="Steve";     Last="Hall";        Title="Benefits Coordinator";       Phone="555-3005"; EmpID="E3005" },
    @{ Sam="tina.allen";       First="Tina";      Last="Allen";       Title="HRIS Analyst";               Phone="555-3006"; EmpID="E3006" },
    @{ Sam="uma.young";        First="Uma";       Last="Young";       Title="Training Coordinator";       Phone="555-3007"; EmpID="E3007" },
    @{ Sam="victor.king";      First="Victor";    Last="King";        Title="Employee Relations Specialist";Phone="555-3008"; EmpID="E3008" }
)
foreach ($u in $hrUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "HR" -Title $u.Title -Path $ouHR `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-B"
}

# ── Legal & Compliance Department ─────────────────────────────────────────
$legalUsers = @(
    @{ Sam="wendy.scott";      First="Wendy";     Last="Scott";       Title="General Counsel";            Phone="555-4001"; EmpID="E4001" },
    @{ Sam="xander.baker";     First="Xander";    Last="Baker";       Title="Corporate Attorney";         Phone="555-4002"; EmpID="E4002" },
    @{ Sam="yvonne.nelson";    First="Yvonne";    Last="Nelson";      Title="Compliance Manager";         Phone="555-4003"; EmpID="E4003" },
    @{ Sam="zack.carter";      First="Zack";      Last="Carter";      Title="Privacy Officer";            Phone="555-4004"; EmpID="E4004" },
    @{ Sam="abby.perez";       First="Abby";      Last="Perez";       Title="Compliance Analyst";         Phone="555-4005"; EmpID="E4005" },
    @{ Sam="brad.roberts";     First="Brad";      Last="Roberts";     Title="Contract Specialist";        Phone="555-4006"; EmpID="E4006" }
)
foreach ($u in $legalUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Legal" -Title $u.Title -Path $ouLegal `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-C"
}

# ── Operations Department ──────────────────────────────────────────────────
$opsUsers = @(
    @{ Sam="chad.evans";       First="Chad";      Last="Evans";       Title="VP Operations";              Phone="555-5001"; EmpID="E5001" },
    @{ Sam="donna.collins";    First="Donna";     Last="Collins";     Title="Operations Manager";         Phone="555-5002"; EmpID="E5002" },
    @{ Sam="ed.stewart";       First="Ed";        Last="Stewart";     Title="Facilities Manager";         Phone="555-5003"; EmpID="E5003" },
    @{ Sam="faye.morris";      First="Faye";      Last="Morris";      Title="Procurement Specialist";     Phone="555-5004"; EmpID="E5004" },
    @{ Sam="gary.rogers";      First="Gary";      Last="Rogers";      Title="Logistics Coordinator";      Phone="555-5005"; EmpID="E5005" },
    @{ Sam="helen.reed";       First="Helen";     Last="Reed";        Title="Supply Chain Analyst";       Phone="555-5006"; EmpID="E5006" },
    @{ Sam="ivan.cook";        First="Ivan";      Last="Cook";        Title="Operations Analyst";         Phone="555-5007"; EmpID="E5007" },
    @{ Sam="julia.bell";       First="Julia";     Last="Bell";        Title="Business Analyst";           Phone="555-5008"; EmpID="E5008" },
    @{ Sam="kurt.morgan";      First="Kurt";      Last="Morgan";      Title="Project Manager";            Phone="555-5009"; EmpID="E5009" },
    @{ Sam="lara.hughes";      First="Lara";      Last="Hughes";      Title="Project Coordinator";        Phone="555-5010"; EmpID="E5010" }
)
foreach ($u in $opsUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Operations" -Title $u.Title -Path $ouOps `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-A"
}

# ── Sales Department ───────────────────────────────────────────────────────
$salesUsers = @(
    @{ Sam="marc.price";       First="Marc";      Last="Price";       Title="VP Sales";                   Phone="555-6001"; EmpID="E6001" },
    @{ Sam="nina.fisher";      First="Nina";      Last="Fisher";      Title="Sales Manager";              Phone="555-6002"; EmpID="E6002" },
    @{ Sam="oliver.cox";       First="Oliver";    Last="Cox";         Title="Account Executive";          Phone="555-6003"; EmpID="E6003" },
    @{ Sam="petra.ward";       First="Petra";     Last="Ward";        Title="Account Executive";          Phone="555-6004"; EmpID="E6004" },
    @{ Sam="quinton.sanders";  First="Quinton";   Last="Sanders";     Title="Sales Representative";       Phone="555-6005"; EmpID="E6005" },
    @{ Sam="ruth.price";       First="Ruth";      Last="Price";       Title="Sales Representative";       Phone="555-6006"; EmpID="E6006" },
    @{ Sam="sam.griffin";      First="Sam";       Last="Griffin";     Title="Sales Development Rep";      Phone="555-6007"; EmpID="E6007" },
    @{ Sam="tamara.diaz";      First="Tamara";    Last="Diaz";        Title="Sales Operations Analyst";   Phone="555-6008"; EmpID="E6008" },
    @{ Sam="ulric.hayes";      First="Ulric";     Last="Hayes";       Title="Channel Partner Manager";    Phone="555-6009"; EmpID="E6009" }
)
foreach ($u in $salesUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Sales" -Title $u.Title -Path $ouSales `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-D"
}

# ── Marketing Department ───────────────────────────────────────────────────
$mktUsers = @(
    @{ Sam="vera.brooks";      First="Vera";      Last="Brooks";      Title="Marketing Director";         Phone="555-7001"; EmpID="E7001" },
    @{ Sam="will.kelly";       First="Will";      Last="Kelly";       Title="Brand Manager";              Phone="555-7002"; EmpID="E7002" },
    @{ Sam="xena.ford";        First="Xena";      Last="Ford";        Title="Digital Marketing Specialist";Phone="555-7003"; EmpID="E7003" },
    @{ Sam="yusuf.james";      First="Yusuf";     Last="James";       Title="Content Strategist";         Phone="555-7004"; EmpID="E7004" },
    @{ Sam="zoe.walsh";        First="Zoe";       Last="Walsh";       Title="Graphic Designer";           Phone="555-7005"; EmpID="E7005" },
    @{ Sam="alan.hunt";        First="Alan";      Last="Hunt";        Title="Social Media Manager";       Phone="555-7006"; EmpID="E7006" }
)
foreach ($u in $mktUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Marketing" -Title $u.Title -Path $ouMkt `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-D"
}

# ── Engineering Department ─────────────────────────────────────────────────
$engUsers = @(
    @{ Sam="blake.shaw";       First="Blake";     Last="Shaw";        Title="VP Engineering";             Phone="555-8001"; EmpID="E8001" },
    @{ Sam="cleo.stone";       First="Cleo";      Last="Stone";       Title="Engineering Manager";        Phone="555-8002"; EmpID="E8002" },
    @{ Sam="dan.porter";       First="Dan";       Last="Porter";      Title="Senior Software Engineer";   Phone="555-8003"; EmpID="E8003" },
    @{ Sam="elsa.long";        First="Elsa";      Last="Long";        Title="Senior Software Engineer";   Phone="555-8004"; EmpID="E8004" },
    @{ Sam="finn.woods";       First="Finn";      Last="Woods";       Title="Software Engineer";          Phone="555-8005"; EmpID="E8005" },
    @{ Sam="gina.barnes";      First="Gina";      Last="Barnes";      Title="Software Engineer";          Phone="555-8006"; EmpID="E8006" },
    @{ Sam="hank.ross";        First="Hank";      Last="Ross";        Title="Software Engineer";          Phone="555-8007"; EmpID="E8007" },
    @{ Sam="iris.gray";        First="Iris";      Last="Gray";        Title="QA Engineer";                Phone="555-8008"; EmpID="E8008" },
    @{ Sam="jake.reyes";       First="Jake";      Last="Reyes";       Title="QA Engineer";                Phone="555-8009"; EmpID="E8009" },
    @{ Sam="kira.simmons";     First="Kira";      Last="Simmons";     Title="DevOps Engineer";            Phone="555-8010"; EmpID="E8010" },
    @{ Sam="liam.foster";      First="Liam";      Last="Foster";      Title="Site Reliability Engineer";  Phone="555-8011"; EmpID="E8011" },
    @{ Sam="mia.hayes";        First="Mia";       Last="Hayes";       Title="Data Engineer";              Phone="555-8012"; EmpID="E8012" }
)
foreach ($u in $engUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Engineering" -Title $u.Title -Path $ouEng `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Building-A"
}

# ── Executives ─────────────────────────────────────────────────────────────
$execUsers = @(
    @{ Sam="ceo.arthur";       First="Arthur";    Last="Merritt";     Title="Chief Executive Officer";    Phone="555-9001"; EmpID="E9001" },
    @{ Sam="coo.brenda";       First="Brenda";    Last="Holloway";    Title="Chief Operating Officer";    Phone="555-9002"; EmpID="E9002" },
    @{ Sam="cfo.gerald";       First="Gerald";    Last="Ashby";       Title="Chief Financial Officer";    Phone="555-9003"; EmpID="E9003" },
    @{ Sam="ciso.natasha";     First="Natasha";   Last="Voss";        Title="Chief Information Security Officer";Phone="555-9004"; EmpID="E9004" },
    @{ Sam="cto.raymond";      First="Raymond";   Last="Osei";        Title="Chief Technology Officer";   Phone="555-9005"; EmpID="E9005" },
    @{ Sam="vp.hr.diane";      First="Diane";     Last="Fontaine";    Title="VP Human Resources";         Phone="555-9006"; EmpID="E9006" }
)
foreach ($u in $execUsers) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Executives" -Title $u.Title -Path $ouExec `
        -OfficePhone $u.Phone -EmployeeID $u.EmpID -Office "HQ-Executive-Floor"
}

# ── Contractors ────────────────────────────────────────────────────────────
$contractors = @(
    @{ Sam="ctr.ivan.petrov";  First="Ivan";      Last="Petrov";      Title="Contractor – IT Consultant";  EmpID="C001" },
    @{ Sam="ctr.li.wei";       First="Li";        Last="Wei";         Title="Contractor – Developer";      EmpID="C002" },
    @{ Sam="ctr.amara.diallo"; First="Amara";     Last="Diallo";      Title="Contractor – Data Analyst";   EmpID="C003" },
    @{ Sam="ctr.felix.meyer";  First="Felix";     Last="Meyer";       Title="Contractor – Security Audit"; EmpID="C004" },
    @{ Sam="ctr.sonja.berg";   First="Sonja";     Last="Berg";        Title="Contractor – Network Eng";    EmpID="C005" }
)
foreach ($u in $contractors) {
    New-UserSafe -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
        -Department "Contractors" -Title $u.Title -Path $ouCont `
        -Description "Contractor account – limited access" -EmployeeID $u.EmpID
}

# ── Service Accounts ───────────────────────────────────────────────────────
Write-Step "Creating service accounts..."
$svcAccounts = @(
    @{ Sam="svc.sql.prod";      First="SQL";    Last="Prod";     Title="SQL Server Service – Production";  NeverExpire=$true;  Desc="SQL Server engine account" },
    @{ Sam="svc.sql.dev";       First="SQL";    Last="Dev";      Title="SQL Server Service – Dev";         NeverExpire=$true;  Desc="SQL dev service account" },
    @{ Sam="svc.backup";        First="Backup"; Last="Service";  Title="Veeam Backup Agent";               NeverExpire=$true;  Desc="Backup service – Veeam" },
    @{ Sam="svc.iis.apppool";   First="IIS";    Last="AppPool";  Title="IIS Application Pool Identity";    NeverExpire=$true;  Desc="IIS app pool svc account" },
    @{ Sam="svc.monitoring";    First="Monitoring";Last="Agent"; Title="Monitoring Agent – Zabbix-sim";    NeverExpire=$true;  Desc="Infrastructure monitoring" },
    @{ Sam="svc.print";         First="Print";  Last="Spooler";  Title="Print Spooler Service Account";    NeverExpire=$true;  Desc="Print server service" },
    @{ Sam="svc.deploy";        First="Deploy"; Last="Agent";    Title="Software Deployment Agent";        NeverExpire=$false; Desc="SCCM/Intune-sim deploy" },
    @{ Sam="svc.scan";          First="Scan";   Last="Agent";    Title="Vulnerability Scanner Account";    NeverExpire=$false; Desc="Nessus/Tenable-sim scanner" },
    @{ Sam="svc.exchange";      First="Exchange";Last="Service"; Title="Exchange Transport Service";       NeverExpire=$true;  Desc="Legacy mail relay account" },
    @{ Sam="svc.ldap.bind";     First="LDAP";   Last="Bind";     Title="LDAP Bind Account – App Auth";     NeverExpire=$true;  Desc="Application LDAP bind svc" },
    @{ Sam="svc.scom";          First="SCOM";   Last="Agent";    Title="SCOM Monitoring";                  NeverExpire=$true;  Desc="Operations Manager agent" },
    @{ Sam="svc.script.runner"; First="Script"; Last="Runner";   Title="Scheduled Task Runner";            NeverExpire=$true;  Desc="Runs scheduled PS tasks" }
)
foreach ($u in $svcAccounts) {
    try {
        Get-ADUser -Identity $u.Sam -ErrorAction Stop | Out-Null
        Write-Skip "SvcAcct: $($u.Sam)"
    } catch {
        New-ADUser -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
            -Name $u.Sam -DisplayName $u.Sam -UserPrincipalName "$($u.Sam)@$DomainName" `
            -Description $u.Desc -Title $u.Title -Department "IT" `
            -Path $svcOU -AccountPassword $SecurePwd -Enabled $true `
            -PasswordNeverExpires $u.NeverExpire
        Write-OK "SvcAcct: $($u.Sam) (PwdNeverExpires=$($u.NeverExpire))"
    }
}

# ── Tier 0 Admin Accounts ──────────────────────────────────────────────────
Write-Step "Creating Tier 0 / Tier 1 privileged admin accounts..."
$adminAccounts = @(
    @{ Sam="adm.john.smith";   First="John";    Last="Smith";    Title="IT Director Admin Account";   Path=$t0OU },
    @{ Sam="adm.alice.wu";     First="Alice";   Last="Wu";       Title="SysAdmin – Privileged";       Path=$t0OU },
    @{ Sam="adm.derek.nguyen"; First="Derek";   Last="Nguyen";   Title="SysAdmin – Privileged";       Path=$t0OU },
    @{ Sam="adm.omar.hassan";  First="Omar";    Last="Hassan";   Title="Security Engineer – Admin";   Path=$t0OU },
    @{ Sam="srv.tom.harris";   First="Tom";     Last="Harris";   Title="Network Admin – Tier 1";      Path=$t1OU },
    @{ Sam="srv.ben.carter";   First="Ben";     Last="Carter";   Title="DevOps Engineer – Tier 1";    Path=$t1OU },
    @{ Sam="srv.nat.jones";    First="Natalie"; Last="Jones";    Title="DBA – Tier 1";                Path=$t1OU }
)
foreach ($u in $adminAccounts) {
    try {
        Get-ADUser -Identity $u.Sam -ErrorAction Stop | Out-Null
        Write-Skip "Admin: $($u.Sam)"
    } catch {
        New-ADUser -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
            -Name "$($u.First) $($u.Last) (Admin)" -DisplayName "$($u.First) $($u.Last) (Admin)" `
            -UserPrincipalName "$($u.Sam)@$DomainName" -Description $u.Title `
            -Title $u.Title -Department "IT" -Path $u.Path `
            -AccountPassword $SecurePwd -Enabled $true -PasswordNeverExpires $false
        Write-OK "Admin: $($u.Sam)"
    }
}

# ── Disabled / Offboarded Accounts (MC-002 augmentation) ──────────────────
Write-Step "Creating stale and disabled accounts (GRC audit targets)..."
$staleUsers = @(
    @{ Sam="svc.legacy";         First="Legacy";  Last="Service";  Title="DECOMMISSIONED – Legacy App";   Disable=$false },
    @{ Sam="former.emp.01";      First="Chris";   Last="Lambert";  Title="Former Employee - Sales";       Disable=$false },
    @{ Sam="former.emp.02";      First="Amy";     Last="Nichols";  Title="Former Employee - Finance";     Disable=$false },
    @{ Sam="former.emp.03";      First="Dale";    Last="Ortega";   Title="Former Employee - HR";          Disable=$false },
    @{ Sam="former.emp.04";      First="Elaine";  Last="Park";     Title="Former Employee - Operations";  Disable=$true  },
    @{ Sam="former.emp.05";      First="Gavin";   Last="Qi";       Title="Former Employee - Engineering"; Disable=$true  },
    @{ Sam="test.account.01";    First="Test";    Last="Account1"; Title="TEST ACCOUNT – DO NOT USE";     Disable=$false },
    @{ Sam="test.account.02";    First="Test";    Last="Account2"; Title="TEST ACCOUNT – DO NOT USE";     Disable=$false },
    @{ Sam="admin.old";          First="Old";     Last="Admin";    Title="OLD Admin Account – Orphaned";  Disable=$false },
    @{ Sam="svc.unused.app";     First="Unused";  Last="App";      Title="Decommissioned app service";    Disable=$false }
)
foreach ($u in $staleUsers) {
    try {
        Get-ADUser -Identity $u.Sam -ErrorAction Stop | Out-Null
        Write-Skip "Stale: $($u.Sam)"
    } catch {
        $path = if ($u.Disable) { $ouDis } else { $ouDis }
        New-ADUser -SamAccountName $u.Sam -GivenName $u.First -Surname $u.Last `
            -Name "$($u.First) $($u.Last)" -DisplayName "$($u.First) $($u.Last)" `
            -UserPrincipalName "$($u.Sam)@$DomainName" `
            -Description $u.Title -Title $u.Title -Path $ouDis `
            -AccountPassword $SecurePwd -Enabled (-not $u.Disable)
        if ($u.Disable) { Disable-ADAccount -Identity $u.Sam }
        Write-Finding "Stale account: $($u.Sam) – Enabled=$(-not $u.Disable)"
    }
}
Write-OK "User accounts created (~200 total)."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 4 – GROUP MEMBERSHIPS
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Assigning group memberships..."

# IT staff -> GRP-IT-Staff + helpdesk groups
Add-GroupMemberSafe "GRP-IT-Staff" ($itUsers | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRC-Helpdesk" @("jessica.ford","kevin.moore","rachel.green")
Add-GroupMemberSafe "GRC-Server-Admins" @("adm.alice.wu","adm.derek.nguyen","srv.tom.harris","srv.ben.carter","srv.nat.jones")
Add-GroupMemberSafe "GRC-AD-Operators" @("adm.alice.wu","adm.derek.nguyen")
Add-GroupMemberSafe "GRC-Security-Team" @("linda.chang","omar.hassan","ciso.natasha")
Add-GroupMemberSafe "GRC-Network-Admins" @("tom.harris","adm.derek.nguyen")
Add-GroupMemberSafe "GRC-GPO-Admins" @("adm.alice.wu","adm.john.smith")
Add-GroupMemberSafe "GRC-Backup-Operators" @("svc.backup","srv.ben.carter")
Add-GroupMemberSafe "GPO-Exempt-USB-Block" @("alice.wu","derek.nguyen","tom.harris","ben.carter","nat.jones","omar.hassan")
Add-GroupMemberSafe "GPO-Apply-DevTools" @("ben.carter","kira.simmons","liam.foster","dan.porter","elsa.long","finn.woods","gina.barnes","hank.ross")

# Department staff groups
Add-GroupMemberSafe "GRP-Finance-Staff"    ($finUsers  | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-HR-Staff"         ($hrUsers   | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Legal-Staff"      ($legalUsers| Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Operations-Staff" ($opsUsers  | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Sales-Staff"      ($salesUsers| Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Marketing-Staff"  ($mktUsers  | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Engineering-Staff"($engUsers  | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Executives"       ($execUsers | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "GRP-Contractors"      ($contractors| Select-Object -ExpandProperty Sam)

# All employees (nested groups)
Add-GroupMemberSafe "GRP-All-Employees" @(
    "GRP-IT-Staff","GRP-Finance-Staff","GRP-HR-Staff","GRP-Legal-Staff",
    "GRP-Operations-Staff","GRP-Sales-Staff","GRP-Marketing-Staff",
    "GRP-Engineering-Staff","GRP-Executives"
)

# Role groups
Add-GroupMemberSafe "ROLE-Privileged-Users" @(
    "adm.john.smith","adm.alice.wu","adm.derek.nguyen","adm.omar.hassan",
    "srv.tom.harris","srv.ben.carter","srv.nat.jones"
)
Add-GroupMemberSafe "ROLE-Finance-SOX-Scope" @(
    "sarah.johnson","mike.brown","emily.davis","carlos.rivera",
    "diana.clark","grace.lee","henry.wilson","cfo.gerald"
)
Add-GroupMemberSafe "ROLE-HR-Sensitive-Data" @(
    "mary.thompson","paul.jackson","tina.allen","vp.hr.diane"
)
Add-GroupMemberSafe "ROLE-Remote-Workers" @(
    "dan.porter","elsa.long","kira.simmons","liam.foster",
    "ctr.ivan.petrov","ctr.li.wei","ctr.amara.diallo","marc.price","nina.fisher"
)
Add-GroupMemberSafe "ROLE-Exec-IT-Access" ($execUsers | Select-Object -ExpandProperty Sam)
Add-GroupMemberSafe "ROLE-Dev-Workstations" @(
    "dan.porter","elsa.long","finn.woods","gina.barnes","hank.ross",
    "kira.simmons","liam.foster","mia.hayes","jake.reyes","ben.carter"
)
Add-GroupMemberSafe "GPO-Apply-ExecProfile" ($execUsers | Select-Object -ExpandProperty Sam)

# File share groups
Add-GroupMemberSafe "FS-Finance-ReadWrite"   @("GRP-Finance-Staff")
Add-GroupMemberSafe "FS-Finance-ReadOnly"    @("GRP-Executives","GRC-Audit-ReadOnly","yvonne.nelson","abby.perez")
Add-GroupMemberSafe "FS-HR-Confidential"     @("GRP-HR-Staff","GRP-Executives")
Add-GroupMemberSafe "FS-Legal-Confidential"  @("GRP-Legal-Staff","GRP-Executives")
Add-GroupMemberSafe "FS-Engineering-Repos"   @("GRP-Engineering-Staff","GRC-Server-Admins")
Add-GroupMemberSafe "FS-IT-Admin-Share"      @("GRC-Server-Admins","GRC-AD-Operators","GRC-Network-Admins")
Add-GroupMemberSafe "FS-Shared-General"      @("GRP-All-Employees","GRP-Contractors")

# App groups
Add-GroupMemberSafe "APP-ERP-Users"          @("GRP-Finance-Staff","GRP-Operations-Staff","GRP-Executives")
Add-GroupMemberSafe "APP-ERP-Admins"         @("nat.jones","mike.brown","adm.alice.wu")
Add-GroupMemberSafe "APP-CRM-Users"          @("GRP-Sales-Staff","GRP-Marketing-Staff","GRP-Executives")
Add-GroupMemberSafe "APP-ITSM-Users"         @("GRP-IT-Staff","ROLE-Privileged-Users")
Add-GroupMemberSafe "APP-ITSM-Admins"        @("adm.john.smith","adm.alice.wu")
Add-GroupMemberSafe "APP-VPN-Users"          @("ROLE-Remote-Workers","GRC-Server-Admins")
Add-GroupMemberSafe "APP-RDP-Servers"        @("GRC-Server-Admins","GRC-AD-Operators")
Add-GroupMemberSafe "APP-SQL-ReadOnly"       @("emily.davis","irene.martin","GRC-Audit-ReadOnly")
Add-GroupMemberSafe "APP-SQL-ReadWrite"      @("nat.jones","svc.sql.prod","APP-ERP-Admins")
Add-GroupMemberSafe "APP-SharePoint-Members" @("GRP-All-Employees")
Add-GroupMemberSafe "APP-SharePoint-Owners"  @("GRP-IT-Staff","GRP-Executives")

# GRC Audit ReadOnly
Add-GroupMemberSafe "GRC-Audit-ReadOnly" @(
    "yvonne.nelson","abby.perez","zack.carter","ctr.felix.meyer","ciso.natasha"
)

# Distribution lists
Add-GroupMemberSafe "DL-All-Staff"           @("GRP-All-Employees")
Add-GroupMemberSafe "DL-IT-Department"       @("GRP-IT-Staff")
Add-GroupMemberSafe "DL-Finance-Department"  @("GRP-Finance-Staff")
Add-GroupMemberSafe "DL-HR-Department"       @("GRP-HR-Staff")
Add-GroupMemberSafe "DL-Executives"          @("GRP-Executives")
Add-GroupMemberSafe "DL-Security-Alerts"     @("GRC-Security-Team","ciso.natasha","adm.john.smith")
Add-GroupMemberSafe "DL-Helpdesk-Queue"      @("GRC-Helpdesk","adm.john.smith")
Add-GroupMemberSafe "DL-Engineering-Team"    @("GRP-Engineering-Staff")

Write-OK "Group memberships assigned."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 5 – COMPUTER OBJECTS
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Creating computer objects..."

# Desktops – Win10
$win10Desktops = @(
    @{ Name="DESK-IT-001";    Loc="HQ-A-IT";       Desc="John Smith – IT Director" },
    @{ Name="DESK-IT-002";    Loc="HQ-A-IT";       Desc="Alice Wu – SysAdmin" },
    @{ Name="DESK-IT-003";    Loc="HQ-A-IT";       Desc="Derek Nguyen – SysAdmin" },
    @{ Name="DESK-IT-004";    Loc="HQ-A-IT";       Desc="Tom Harris – NetAdmin" },
    @{ Name="DESK-IT-005";    Loc="HQ-A-IT";       Desc="Linda Chang – Security" },
    @{ Name="DESK-FIN-001";   Loc="HQ-B-Finance";  Desc="Mike Brown – Controller" },
    @{ Name="DESK-FIN-002";   Loc="HQ-B-Finance";  Desc="Emily Davis – Sr Accountant" },
    @{ Name="DESK-FIN-003";   Loc="HQ-B-Finance";  Desc="Carlos Rivera – Accountant" },
    @{ Name="DESK-FIN-004";   Loc="HQ-B-Finance";  Desc="Grace Lee – Payroll Mgr" },
    @{ Name="DESK-HR-001";    Loc="HQ-B-HR";       Desc="Mary Thompson – HR Director" },
    @{ Name="DESK-HR-002";    Loc="HQ-B-HR";       Desc="Paul Jackson – HR BP" },
    @{ Name="DESK-HR-003";    Loc="HQ-B-HR";       Desc="Quinn Adams – Recruiter" },
    @{ Name="DESK-LGL-001";   Loc="HQ-C-Legal";    Desc="Wendy Scott – General Counsel" },
    @{ Name="DESK-LGL-002";   Loc="HQ-C-Legal";    Desc="Yvonne Nelson – Compliance Mgr" },
    @{ Name="DESK-OPS-001";   Loc="HQ-A-Ops";      Desc="Chad Evans – VP Ops" },
    @{ Name="DESK-OPS-002";   Loc="HQ-A-Ops";      Desc="Donna Collins – Ops Mgr" },
    @{ Name="DESK-OPS-003";   Loc="HQ-A-Ops";      Desc="Kurt Morgan – PM" },
    @{ Name="DESK-SAL-001";   Loc="HQ-D-Sales";    Desc="Marc Price – VP Sales" },
    @{ Name="DESK-SAL-002";   Loc="HQ-D-Sales";    Desc="Nina Fisher – Sales Mgr" },
    @{ Name="DESK-MKT-001";   Loc="HQ-D-Marketing";Desc="Vera Brooks – Marketing Dir" }
)
foreach ($c in $win10Desktops) {
    New-ComputerSafe -Name $c.Name -Path $ouDeskW10 -Description $c.Desc -Location $c.Loc
}

# Desktops – Win11
$win11Desktops = @(
    @{ Name="DESK-ENG-001";   Loc="HQ-A-Engineering";  Desc="Dan Porter – Sr SWE" },
    @{ Name="DESK-ENG-002";   Loc="HQ-A-Engineering";  Desc="Elsa Long – Sr SWE" },
    @{ Name="DESK-ENG-003";   Loc="HQ-A-Engineering";  Desc="Finn Woods – SWE" },
    @{ Name="DESK-ENG-004";   Loc="HQ-A-Engineering";  Desc="Ben Carter – DevOps" },
    @{ Name="DESK-ENG-005";   Loc="HQ-A-Engineering";  Desc="Kira Simmons – DevOps" },
    @{ Name="DESK-IT-W11-001";Loc="HQ-A-IT";           Desc="Omar Hassan – Security Eng" },
    @{ Name="DESK-IT-W11-002";Loc="HQ-A-IT";           Desc="Ben Carter – DevOps" }
)
foreach ($c in $win11Desktops) {
    New-ComputerSafe -Name $c.Name -Path $ouDeskW11 -Description $c.Desc -Location $c.Loc `
        -OS "Windows 11 Enterprise" -OSVersion "10.0 (22621)"
}

# Laptops
$laptops = @(
    @{ Name="LAPTOP-EXEC-001"; Loc="Executive Floor"; Desc="CEO Arthur Merritt" },
    @{ Name="LAPTOP-EXEC-002"; Loc="Executive Floor"; Desc="CFO Gerald Ashby" },
    @{ Name="LAPTOP-EXEC-003"; Loc="Executive Floor"; Desc="CTO Raymond Osei" },
    @{ Name="LAPTOP-EXEC-004"; Loc="Executive Floor"; Desc="CISO Natasha Voss" },
    @{ Name="LAPTOP-SAL-001";  Loc="Remote/Sales";    Desc="Oliver Cox – AE" },
    @{ Name="LAPTOP-SAL-002";  Loc="Remote/Sales";    Desc="Petra Ward – AE" },
    @{ Name="LAPTOP-ENG-001";  Loc="Remote/Eng";      Desc="Liam Foster – SRE" },
    @{ Name="LAPTOP-ENG-002";  Loc="Remote/Eng";      Desc="Mia Hayes – Data Eng" },
    @{ Name="LAPTOP-CTR-001";  Loc="Remote";          Desc="Ivan Petrov – Contractor" },
    @{ Name="LAPTOP-CTR-002";  Loc="Remote";          Desc="Li Wei – Contractor" }
)
foreach ($c in $laptops) {
    New-ComputerSafe -Name $c.Name -Path $ouLaptops -Description $c.Desc -Location $c.Loc `
        -OS "Windows 11 Enterprise" -OSVersion "10.0 (22621)"
}

# Servers
$appServers = @(
    @{ Name="SRV-SQL-01";     Loc="DC-Rack-A"; Desc="SQL Server 2019 – Production ERP DB";    OS="Windows Server 2019 Standard" },
    @{ Name="SRV-SQL-02";     Loc="DC-Rack-A"; Desc="SQL Server 2019 – Reporting";             OS="Windows Server 2019 Standard" },
    @{ Name="SRV-APP-ERP";    Loc="DC-Rack-B"; Desc="ERP Application Server";                 OS="Windows Server 2022 Standard" },
    @{ Name="SRV-APP-ITSM";   Loc="DC-Rack-B"; Desc="ITSM / ServiceDesk Application";         OS="Windows Server 2022 Standard" },
    @{ Name="SRV-SCCM";       Loc="DC-Rack-C"; Desc="Software Deployment / SCCM-sim";         OS="Windows Server 2019 Standard" }
)
foreach ($c in $appServers) {
    New-ComputerSafe -Name $c.Name -Path $ouSrvApp -Description $c.Desc -Location $c.Loc -OS $c.OS
}

$fileServers = @(
    @{ Name="SRV-FS-01";      Loc="DC-Rack-A"; Desc="Primary File Server – DFS Root";         OS="Windows Server 2019 Standard" },
    @{ Name="SRV-FS-02";      Loc="DC-Rack-A"; Desc="File Server – Replica / DFS Target";     OS="Windows Server 2019 Standard" },
    @{ Name="SRV-PRINT-01";   Loc="HQ-A-IT";   Desc="Print Server";                           OS="Windows Server 2019 Standard" }
)
foreach ($c in $fileServers) {
    New-ComputerSafe -Name $c.Name -Path $ouSrvFile -Description $c.Desc -Location $c.Loc -OS $c.OS
}

$webServers = @(
    @{ Name="SRV-WEB-01";     Loc="DMZ-Rack-A"; Desc="IIS Web Server – Intranet";             OS="Windows Server 2019 Standard" },
    @{ Name="SRV-WEB-02";     Loc="DMZ-Rack-A"; Desc="IIS Web Server – Dev/Staging";          OS="Windows Server 2019 Standard" }
)
foreach ($c in $webServers) {
    New-ComputerSafe -Name $c.Name -Path $ouSrvWeb -Description $c.Desc -Location $c.Loc -OS $c.OS
}

$kiosks = @(
    @{ Name="KIOSK-LOBBY-01"; Loc="HQ-Lobby";   Desc="Lobby visitor check-in kiosk" },
    @{ Name="KIOSK-CONF-01";  Loc="HQ-Conf-A";  Desc="Conference room A display/booking" },
    @{ Name="KIOSK-CONF-02";  Loc="HQ-Conf-B";  Desc="Conference room B display/booking" }
)
foreach ($c in $kiosks) {
    New-ComputerSafe -Name $c.Name -Path $ouKiosks -Description $c.Desc -Location $c.Loc `
        -OS "Windows 10 Enterprise LTSC" -OSVersion "10.0 (17763)"
}

Write-OK "Computer objects created (~50 total)."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 6 – FINE-GRAINED PASSWORD POLICIES (PSOs)
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Creating Fine-Grained Password Policies (PSOs)..."

function New-PSO {
    param([string]$Name, [int]$Precedence, [int]$MinLen, [int]$History,
          [int]$MaxAgeDays, [bool]$Complex, [int]$LockoutThresh,
          [int]$LockoutMins, [string]$Description)
    try {
        Get-ADFineGrainedPasswordPolicy -Identity $Name -ErrorAction Stop | Out-Null
        Write-Skip "PSO: $Name"
    } catch {
        New-ADFineGrainedPasswordPolicy -Name $Name `
            -Precedence $Precedence `
            -MinPasswordLength $MinLen `
            -PasswordHistoryCount $History `
            -MaxPasswordAge (New-TimeSpan -Days $MaxAgeDays) `
            -MinPasswordAge (New-TimeSpan -Days 1) `
            -ComplexityEnabled $Complex `
            -ReversibleEncryptionEnabled $false `
            -LockoutThreshold $LockoutThresh `
            -LockoutDuration (New-TimeSpan -Minutes $LockoutMins) `
            -LockoutObservationWindow (New-TimeSpan -Minutes $LockoutMins) `
            -Description $Description `
            -ProtectedFromAccidentalDeletion $false
        Write-OK "PSO: $Name (MinLen=$MinLen, MaxAge=$MaxAgeDays days, Precedence=$Precedence)"
    }
}

# PSO 1: Privileged admin accounts – strictest
New-PSO -Name "PSO-Privileged-Accounts" -Precedence 1 `
    -MinLen 20 -History 24 -MaxAgeDays 30 -Complex $true `
    -LockoutThresh 3 -LockoutMins 30 `
    -Description "Strict policy for Tier 0/1 admin accounts – CIS Level 2"

# PSO 2: Service accounts – long, no expiry override (for lab purposes)
New-PSO -Name "PSO-Service-Accounts" -Precedence 5 `
    -MinLen 25 -History 0 -MaxAgeDays 0 -Complex $true `
    -LockoutThresh 0 -LockoutMins 0 `
    -Description "Service account policy – long passwords, no expiry (override per svc)"

# PSO 3: Finance/SOX scope users – elevated
New-PSO -Name "PSO-Finance-SOX" -Precedence 10 `
    -MinLen 16 -History 20 -MaxAgeDays 45 -Complex $true `
    -LockoutThresh 5 -LockoutMins 15 `
    -Description "Finance/SOX in-scope user accounts – SOX compliance password policy"

# PSO 4: Contractors – shorter lifespan
New-PSO -Name "PSO-Contractors" -Precedence 20 `
    -MinLen 14 -History 10 -MaxAgeDays 30 -Complex $true `
    -LockoutThresh 5 -LockoutMins 15 `
    -Description "Contractor accounts – 30-day max password age, limited history"

# Apply PSOs to groups
try { Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Privileged-Accounts" -Subjects "ROLE-Privileged-Users"; Write-OK "PSO applied: PSO-Privileged-Accounts -> ROLE-Privileged-Users" } catch { Write-Skip "PSO-Privileged-Accounts already applied" }
try { Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Service-Accounts"    -Subjects $svcAccounts[0..5].Sam; Write-OK "PSO applied: PSO-Service-Accounts" } catch { Write-Skip "PSO-Service-Accounts already applied" }
try { Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Finance-SOX"         -Subjects "ROLE-Finance-SOX-Scope"; Write-OK "PSO applied: PSO-Finance-SOX -> ROLE-Finance-SOX-Scope" } catch { Write-Skip "PSO-Finance-SOX already applied" }
try { Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Contractors"         -Subjects "GRP-Contractors"; Write-OK "PSO applied: PSO-Contractors -> GRP-Contractors" } catch { Write-Skip "PSO-Contractors already applied" }

Write-OK "PSOs created and applied."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 7 – GROUP POLICY OBJECTS
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "Creating and linking Group Policy Objects..."

Import-Module GroupPolicy -ErrorAction SilentlyContinue

function New-GPOSafe {
    param([string]$Name, [string]$Comment)
    $existing = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if ($existing) { Write-Skip "GPO: $Name"; return $existing }
    $gpo = New-GPO -Name $Name -Comment $Comment
    Write-OK "GPO: $Name"
    return $gpo
}

function Link-GPOSafe {
    param([string]$Name, [string]$Target)
    try {
        New-GPLink -Name $Name -Target $Target -ErrorAction Stop | Out-Null
        Write-OK "GPO Link: $Name -> $Target"
    } catch {
        Write-Skip "GPO Link: $Name -> $Target"
    }
}

$gpo1  = New-GPOSafe "GPO-Domain-Default-Security"        "Domain-wide baseline security settings"
$gpo2  = New-GPOSafe "GPO-DC-Baseline"                    "Domain Controller security and audit baseline"
$gpo3  = New-GPOSafe "GPO-Workstation-Baseline"           "Workstation CIS Level 1 baseline settings"
$gpo4  = New-GPOSafe "GPO-Server-Baseline"                "Member server CIS Level 1 baseline settings"
$gpo5  = New-GPOSafe "GPO-Exec-Desktop-Profile"           "Executive desktop profile and branding"
$gpo6  = New-GPOSafe "GPO-Dev-Workstations"               "Engineering – developer tools and elevated rights"
$gpo7  = New-GPOSafe "GPO-Kiosk-Lockdown"                 "Kiosk restricted shell and logon settings"
$gpo8  = New-GPOSafe "GPO-Contractor-Restrictions"        "Contractor account access restrictions"
$gpo9  = New-GPOSafe "GPO-Finance-Drive-Map"              "Finance department drive mapping"
$gpo10 = New-GPOSafe "GPO-IT-Admin-Tools"                 "IT admin tools deployment – exempt from restrictions"
$gpo11 = New-GPOSafe "GPO-Windows-Update-Servers"         "Windows Update policy for servers – WSUS"
$gpo12 = New-GPOSafe "GPO-AppLocker-Workstations"         "AppLocker rules for standard workstations"

# Configure basic registry settings in each GPO via Set-GPRegistryValue
# Workstation Baseline – enable audit policies and screen lock
try {
    # Screen lock after 15 min inactivity
    Set-GPRegistryValue -Name "GPO-Workstation-Baseline" `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -ValueName "InactivityTimeoutSecs" -Type DWord -Value 900 | Out-Null

    # Disable autorun/autoplay
    Set-GPRegistryValue -Name "GPO-Workstation-Baseline" `
        -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
        -ValueName "NoDriveTypeAutoRun" -Type DWord -Value 255 | Out-Null

    # Disable guest account via policy
    Set-GPRegistryValue -Name "GPO-DC-Baseline" `
        -Key "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" `
        -ValueName "LimitBlankPasswordUse" -Type DWord -Value 1 | Out-Null

    # Enable NTLMv2 only
    Set-GPRegistryValue -Name "GPO-DC-Baseline" `
        -Key "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" `
        -ValueName "LmCompatibilityLevel" -Type DWord -Value 5 | Out-Null

    Write-OK "GPO registry values set."
} catch {
    Write-Warning "Could not set some GPO registry values (non-fatal): $_"
}

# Link GPOs to OUs
Link-GPOSafe "GPO-Domain-Default-Security"  $DomainDN
Link-GPOSafe "GPO-DC-Baseline"              "OU=Domain Controllers,$DomainDN"
Link-GPOSafe "GPO-Workstation-Baseline"     $compOU
Link-GPOSafe "GPO-Server-Baseline"          $compOU
Link-GPOSafe "GPO-Exec-Desktop-Profile"     $ouExec
Link-GPOSafe "GPO-Dev-Workstations"         $ouDeskW11
Link-GPOSafe "GPO-Kiosk-Lockdown"           $ouKiosks
Link-GPOSafe "GPO-Contractor-Restrictions"  $ouCont
Link-GPOSafe "GPO-Finance-Drive-Map"        $ouFin
Link-GPOSafe "GPO-IT-Admin-Tools"           $ouIT
Link-GPOSafe "GPO-Windows-Update-Servers"   $ouSrvApp
Link-GPOSafe "GPO-AppLocker-Workstations"   $ouDeskW10

Write-OK "GPOs created and linked."


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 8 – INTENTIONAL MISCONFIGURATIONS (GRC Audit Targets)
# ═════════════════════════════════════════════════════════════════════════════
if ($SeedMisconfigurations) {
    Write-Step "Seeding intentional GRC audit findings..."

    # MC-001: Weak domain password policy
    Write-Finding "MC-001: Setting weak domain password policy (min 8, no complexity, 180 day max)"
    Set-ADDefaultDomainPasswordPolicy -Identity $DomainName `
        -MinPasswordLength 8 `
        -PasswordHistoryCount 5 `
        -MaxPasswordAge (New-TimeSpan -Days 180) `
        -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $false `
        -ReversibleEncryptionEnabled $false

    # MC-003: Domain Users added to a local admin group via nesting
    # (done on workstations via Ansible role – flagged here for awareness)
    Write-Finding "MC-003: Domain Users -> local Administrators (applied via workstation Ansible role)"

    # MC-009: Several service accounts already created with PwdNeverExpires=$true above

    # MC-011: Orphaned/disabled accounts still member of privileged groups
    Write-Finding "MC-011: Adding stale account to sensitive group (audit finding)"
    Add-GroupMemberSafe "APP-ERP-Admins" @("admin.old")          # orphaned admin in app admin group
    Add-GroupMemberSafe "FS-Finance-ReadWrite" @("former.emp.02") # former finance employee still has access
    Add-GroupMemberSafe "APP-SQL-ReadWrite" @("svc.unused.app")   # decomm'd service acct still has DB write

    # MC-012: Excessive privileged group members – more than expected in Domain Admins
    Write-Finding "MC-012: Extra accounts added directly to Domain Admins (should use ROLE-Privileged-Users)"
    Add-GroupMemberSafe "Domain Admins" @("nat.jones","ben.carter","derek.nguyen")

    # MC-013: Nested group membership creates hidden privilege path
    Write-Finding "MC-013: GRP-IT-Staff nested into APP-ERP-Admins (all IT staff get ERP admin)"
    Add-GroupMemberSafe "APP-ERP-Admins" @("GRP-IT-Staff")

    # MC-014: Service account used as interactive logon – member of Remote Desktop Users
    Write-Finding "MC-014: Service account svc.sql.prod added to Remote Desktop Users"
    Add-GroupMemberSafe "APP-RDP-Servers" @("svc.sql.prod","svc.ldap.bind")

    # MC-015: Test accounts enabled and in sensitive groups
    Write-Finding "MC-015: Test accounts still active and added to staff groups"
    Add-GroupMemberSafe "GRP-IT-Staff" @("test.account.01","test.account.02")
    Add-GroupMemberSafe "FS-IT-Admin-Share" @("test.account.01")

    Write-OK "Misconfigurations seeded."
} else {
    Write-Host "`n    [i] Skipping misconfigurations. Re-run with -SeedMisconfigurations to add findings." -ForegroundColor DarkGray
}


# ═════════════════════════════════════════════════════════════════════════════
# SECTION 9 – SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
Write-Step "AD Population Complete – Summary"

$userCount  = (Get-ADUser -Filter *).Count
$groupCount = (Get-ADGroup -Filter *).Count
$compCount  = (Get-ADComputer -Filter *).Count
$ouCount    = (Get-ADOrganizationalUnit -Filter *).Count
$gpoCount   = (Get-GPO -All).Count
$psoCount   = (Get-ADFineGrainedPasswordPolicy -Filter *).Count

Write-Host @"

  ╔══════════════════════════════════════════════════════════╗
  ║           GRC Lab – Active Directory Summary             ║
  ╠══════════════════════════════════════════════════════════╣
  ║  Domain          : $DomainName
  ║  Users           : $userCount
  ║  Groups          : $groupCount
  ║  Computers       : $compCount
  ║  OUs             : $ouCount
  ║  GPOs            : $gpoCount
  ║  PSOs            : $psoCount
  ╠══════════════════════════════════════════════════════════╣
  ║  Departments     : IT, Finance, HR, Legal, Ops,         ║
  ║                    Sales, Marketing, Engineering,        ║
  ║                    Executives, Contractors               ║
  ║  Privileged Accts: Tier 0 (adm.*) + Tier 1 (srv.*)      ║
  ║  Service Accounts: 12 (svc.*)                            ║
  ║  Stale Accounts  : 10 (Disabled OU / former.emp / test)  ║
  ╠══════════════════════════════════════════════════════════╣
  ║  GRC Findings Seeded: $(if($SeedMisconfigurations){'YES (MC-001 through MC-015)     '}else{'NO  (re-run with -SeedMisconfigurations)'})
  ╚══════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "[DONE] Run your audit scripts against DC-PRIMARY (10.10.10.10)`n" -ForegroundColor Green
