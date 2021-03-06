Configuration ArcGISPortal
{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $ServiceCredential,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $ServiceCredentialIsDomainAccount = $false,

        [Parameter(Mandatory=$false)]
        [System.Boolean]
        $ServiceCredentialIsMSA = $false,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential,

        [Parameter(Mandatory=$True)]
        [System.String]
        $Version,
        
        [Parameter(Mandatory=$False)]
        [System.String]
        $PrimaryPortalMachine,

        [Parameter(Mandatory=$False)]
        [System.String]
        $ContentDirectoryLocation,

        [Parameter(Mandatory=$False)]
        [System.String]
        $AdminEmail,

        [Parameter(Mandatory=$False)]
        [System.Byte]
        $AdminSecurityQuestionIndex,
        
        [Parameter(Mandatory=$False)]
        [System.String]
        $AdminSecurityAnswer,

        [Parameter(Mandatory=$False)]
        [System.String]
        $LicenseFilePath,

        [Parameter(Mandatory=$False)]
        [System.String]
        $UserLicenseTypeId,

        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $ADServiceCredential,

        [Parameter(Mandatory=$False)]
        [System.Boolean]
        $EnableAutomaticAccountCreation,

        [Parameter(Mandatory=$False)]
        [System.String]
        $DefaultRoleForUser,

        [Parameter(Mandatory=$False)]
        [System.String]
        $DefaultUserLicenseTypeIdForUser,

        [Parameter(Mandatory=$False)]
        [System.Boolean]
        $DisableServiceDirectory,

        [Parameter(Mandatory=$False)]
        [System.Object]
        $SslRootOrIntermediate,

        [Parameter(Mandatory=$False)]
        [ValidateSet("AzureFiles","AzureBlob")]
        [AllowNull()] 
        [System.String]
        $CloudStorageType,

        [System.String]
        $AzureFileShareName,

        [System.String]
        $CloudNamespace,

        [Parameter(Mandatory=$False)]
        [System.Management.Automation.PSCredential]
        $CloudStorageCredentials,
        
        [Parameter(Mandatory=$False)]
        [System.Boolean]
        $DebugMode = $False
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName @{ModuleName="ArcGIS";ModuleVersion="3.0.0"}
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_Portal
    Import-DscResource -Name ArcGIS_WindowsService
    Import-DscResource -Name ArcGIS_Service_Account

    if(($null -ne $CloudStorageType) -and $CloudStorageCredentials) 
    {
        $AccountName = $CloudStorageCredentials.UserName
		$EndpointSuffix = ''
        $Pos = $CloudStorageCredentials.UserName.IndexOf('.blob.')
        if($Pos -gt -1) {
            $AccountName = $CloudStorageCredentials.UserName.Substring(0, $Pos)
			$EndpointSuffix = $CloudStorageCredentials.UserName.Substring($Pos + 6) # Remove the hostname and .blob. suffix to get the storage endpoint suffix
			$EndpointSuffix = ";EndpointSuffix=$($EndpointSuffix)"
        }

        if($CloudStorageType -ieq 'AzureFiles') {
            $AzureFilesEndpoint = if($Pos -gt -1){$CloudStorageCredentials.UserName.Replace('.blob.','.file.')}else{$CloudStorageCredentials.UserName}
            $AzureFileShareName = $AzureFileShareName.ToLower() # Azure file shares need to be lower case
            $ContentDirectoryLocation = "\\$($AzureFilesEndpoint)\$AzureFileShareName\$($CloudNamespace)\portal\content"    
        }
        else {
            $AccountKey = $CloudStorageCredentials.GetNetworkCredential().Password
            $ContentDirectoryCloudConnectionString = "DefaultEndpointsProtocol=https;AccountName=$($AccountName);AccountKey=$($AccountKey)$($EndpointSuffix)"
		    $ContentDirectoryCloudContainerName = "arcgis-portal-content-$($CloudNamespace)portal"
        }
    }


    Node $AllNodes.NodeName
    {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }
        
        $MachineFQDN = Get-FQDN $Node.NodeName
        $IsMultiMachinePortal = (($AllNodes | Measure-Object).Count -gt 1)
        
        $Depends = @()
        ArcGIS_xFirewall Portal_FirewallRules
        {
            Name                  = "PortalforArcGIS" 
            DisplayName           = "Portal for ArcGIS" 
            DisplayGroup          = "Portal for ArcGIS" 
            Ensure                = 'Present'
            Access                = "Allow" 
            State                 = "Enabled" 
            Profile               = ("Domain","Private","Public")
            LocalPort             = ("7080","7443","7654")                         
            Protocol              = "TCP" 
        }
        $Depends += @('[ArcGIS_xFirewall]Portal_FirewallRules')
        
        if($IsMultiMachinePortal) 
        {
            ArcGIS_xFirewall Portal_Database_OutBound
            {
                Name                  = "PortalforArcGIS-Outbound" 
                DisplayName           = "Portal for ArcGIS Outbound" 
                DisplayGroup          = "Portal for ArcGIS Outbound" 
                Ensure                = 'Present' 
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public")
                RemotePort            = ("7120","7220", "7005", "7099", "7199", "5701", "5702", "5703")  # Elastic Search uses 7120,7220 and Postgres uses 7654 for replication, Hazelcast uses 5701 and 5702 (extra 2 ports for situations where unable to get port)
                Direction             = "Outbound"                       
                Protocol              = "TCP" 
            }  
            $Depends += @('[ArcGIS_xFirewall]Portal_Database_OutBound')
            
            ArcGIS_xFirewall Portal_Database_InBound
            {
                Name                  = "PortalforArcGIS-Inbound" 
                DisplayName           = "Portal for ArcGIS Inbound" 
                DisplayGroup          = "Portal for ArcGIS Inbound" 
                Ensure                = 'Present' 
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public")
                LocalPort             = ("7120","7220","5701", "5702", "5703")  # Elastic Search uses 7120,7220, Hazelcast uses 5701 and 5702
                Protocol              = "TCP" 
            }  
            $Depends += @('[ArcGIS_xFirewall]Portal_Database_InBound')
        }

        Service Portal_for_ArcGIS_Service
        {
            Name = 'Portal for ArcGIS'
            Credential = $ServiceCredential
            StartupType = 'Automatic'
            State = 'Running'          
            DependsOn = $Depends
        } 

        $Depends += @('[Service]Portal_for_ArcGIS_Service')

        $DataDirsForPortal = @('HKLM:\SOFTWARE\ESRI\Portal for ArcGIS')
        if($ContentDirectoryLocation -and (-not($ContentDirectoryLocation.StartsWith('\'))) -and ($CloudStorageType -ne 'AzureFiles'))
        {
            $DataDirsForPortal += $ContentDirectoryLocation
            $DataDirsForPortal += (Split-Path $ContentDirectoryLocation -Parent)

            File ContentDirectoryLocation
            {
                Ensure = "Present"
                DestinationPath = $ContentDirectoryLocation
                Type = 'Directory'
                DependsOn = $Depends
            }  
            $Depends += "[File]ContentDirectoryLocation"
        }

        ArcGIS_Service_Account Portal_RunAs_Account
        {
            Name = 'Portal for ArcGIS'
            RunAsAccount = $ServiceCredential
            Ensure = "Present"
            DataDir = $DataDirsForPortal
            DependsOn = $Depends
            IsDomainAccount = $ServiceCredentialIsDomainAccount
        }
        
        $Depends += @('[ArcGIS_Service_Account]Portal_RunAs_Account')

        if($AzureFilesEndpoint -and $CloudStorageCredentials -and ($CloudStorageType -ieq 'AzureFiles')) 
        {
            $filesStorageAccountName = $AzureFilesEndpoint.Substring(0, $AzureFilesEndpoint.IndexOf('.'))
            $storageAccountKey       = $CloudStorageCredentials.GetNetworkCredential().Password
    
            Script PersistStorageCredentials
            {
                TestScript = { 
                                $result = cmdkey "/list:$using:AzureFilesEndpoint"
                                $result | ForEach-Object {Write-verbose -Message "cmdkey: $_" -Verbose}
                                if($result -like '*none*')
                                {
                                    return $false
                                }
                                return $true
                            }
                SetScript = { $result = cmdkey "/add:$using:AzureFilesEndpoint" "/user:$using:filesStorageAccountName" "/pass:$using:storageAccountKey" 
                            $result | ForEach-Object {Write-verbose -Message "cmdkey: $_" -Verbose}
                            }
                GetScript            = { return @{} }                  
                DependsOn            = @('[ArcGIS_Service_Account]Portal_Service_Account')
                PsDscRunAsCredential = $ServiceCredential # This is critical, cmdkey must run as the service account to persist property
            }              
            $Depends += '[Script]PersistStorageCredentials'

            $RootPathOfFileShare = "\\$($AzureFilesEndpoint)\$AzureFileShareName"
            Script CreatePortalContentFolder
            {
                TestScript = { 
                                Test-Path $using:ContentDirectoryLocation
                            }
                SetScript = {                   
                                Write-Verbose "Mount to $using:RootPathOfFileShare"
                                $DriveInfo = New-PSDrive -Name 'Z' -PSProvider FileSystem -Root $using:RootPathOfFileShare
                                if(-not(Test-Path $using:ContentDirectoryLocation)) {
                                    Write-Verbose "Creating folder $using:ContentDirectoryLocation"
                                    New-Item $using:ContentDirectoryLocation -ItemType directory
                                }else {
                                    Write-Verbose "Folder '$using:ContentDirectoryLocation' already exists"
                                }
                            }
                GetScript            = { return @{} }     
                PsDscRunAsCredential = $ServiceCredential # This is important, only arcgis account has access to the file share on AFS
            }             
            $Depends += '[Script]CreatePortalContentFolder'
        } 

        if($Node.NodeName -ine $PrimaryPortalMachine)
        {
            WaitForAll "WaitForAllPortal$($PrimaryPortalMachine)"{
                ResourceName = "[ArcGIS_Portal]Portal$($PrimaryPortalMachine)"
                NodeName = $PrimaryPortalMachine
                RetryIntervalSec = 60
                RetryCount = 90
                DependsOn = $Depends
            }
            $Depends += "[WaitForAll]WaitForAllPortal$($PrimaryPortalMachine)"
        }   
        
        ArcGIS_Portal "Portal$($Node.NodeName)"
        {
            Ensure = 'Present'
            PortalHostName = $MachineFQDN
            LicenseFilePath = $LicenseFilePath
            UserLicenseTypeId = $UserLicenseTypeId
            PortalAdministrator = $SiteAdministratorCredential 
            DependsOn =  $Depends
            AdminEmail = $AdminEmail
            AdminSecurityQuestionIndex = $AdminSecurityQuestionIndex
            AdminSecurityAnswer = $AdminSecurityAnswer
            ContentDirectoryLocation = $ContentDirectoryLocation
            Join = if($Node.NodeName -ine $PrimaryPortalMachine) { $true } else { $false } 
            IsHAPortal = if($IsMultiMachinePortal){ $true } else { $false }
            PeerMachineHostName = if($Node.NodeName -ine $PrimaryPortalMachine) { (Get-FQDN $PrimaryPortalMachine) } else { "" } #add peer machine name
            EnableDebugLogging = if($DebugMode) { $true } else { $false }
            ADServiceUser = $ADServiceCredential
            EnableAutomaticAccountCreation = if($EnableAutomaticAccountCreation) { $true } else { $false }
            DefaultRoleForUser = $DefaultRoleForUser
            DefaultUserLicenseTypeIdForUser = $DefaultUserLicenseTypeIdForUser
            DisableServiceDirectory = if($DisableServiceDirectory) { $true } else { $false }
            ContentDirectoryCloudConnectionString = $ContentDirectoryCloudConnectionString							
            ContentDirectoryCloudContainerName    = $ContentDirectoryCloudContainerName
        }
        $Depends += "[ArcGIS_Portal]Portal$($Node.NodeName)"

        if($Node.SSLCertificate){
            ArcGIS_Portal_TLS ArcGIS_Portal_TLS
            {
                Ensure                  = 'Present'
                SiteName                = 'arcgis'
                SiteAdministrator       = $SiteAdministratorCredential 
                CName                   = $Node.SSLCertificate.CName
                CertificateFileLocation = $Node.SSLCertificate.Path
                CertificatePassword     = $Node.SSLCertificate.Password
                DependsOn               = $Depends
                SslRootOrIntermediate   = $SslRootOrIntermediate
            }
        }
    }   
}
