Configuration ArcGISServer
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
        
        [Parameter(Mandatory=$False)]
        [System.String]
        $PrimaryServerMachine,

        [Parameter(Mandatory=$False)]
        [System.String]
        $ServerRole,

        [Parameter(Mandatory=$False)]
        [System.Boolean]
        $OpenFirewallPorts = $False,

        [Parameter(Mandatory=$False)]
        [System.String]
        $ConfigStoreLocation,

        [Parameter(Mandatory=$true)]
        [System.String]
        $ServerDirectoriesRootLocation,

        [Parameter(Mandatory=$false)]
        [System.Array]
        $ServerDirectories,

        [Parameter(Mandatory=$False)]
        [System.String]
        $ServerLogsLocation = $null,

        [Parameter(Mandatory=$False)]
        [System.String]
        $LocalRepositoryPath = $null,
        
        [Parameter(Mandatory=$False)]
        [System.Object]
        $RegisteredDirectories,

        [Parameter(Mandatory=$False)]
        [System.Object]
        $SslRootOrIntermediate,

        [Parameter(Mandatory=$False)]
        [ValidateSet("AzureFiles","AzureBlob")]
        [AllowNull()] 
        [System.String]
        $CloudStorageType,

        [Parameter(Mandatory=$False)]
        [System.String]
        $AzureFileShareName,

        [Parameter(Mandatory=$False)]
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
    Import-DscResource -Name ArcGIS_Server
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
            $AzureFilesEndpoint = if($Pos -gt -1){$StorageAccountCredential.UserName.Replace('.blob.','.file.')}else{$StorageAccountCredential.UserName}                   
            $AzureFileShareName = $AzureFileShareName.ToLower() # Azure file shares need to be lower case
            $ConfigStoreLocation  = "\\$($AzureFilesEndpoint)\$AzureFileShareName\$($CloudNamespace)\server\config-store"
            $ServerDirectoriesRootLocation   = "\\$($AzureFilesEndpoint)\$AzureFileShareName\$($CloudNamespace)\server\server-dirs" 
        }
        else {
            $ConfigStoreCloudStorageConnectionString = "NAMESPACE=$($CloudNamespace)server$($EndpointSuffix);DefaultEndpointsProtocol=https;AccountName=$AccountName"
            $ConfigStoreCloudStorageConnectionSecret = "AccountKey=$($CloudStorageCredentials.GetNetworkCredential().Password)"
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
        $IsMultiMachineServer = (($AllNodes | Measure-Object).Count -gt 1)

        $Depends = @()
        if($OpenFirewallPorts -or $IsMultiMachineServer ) # Server only deployment or behind an ILB or has DataStore nodes that need to register using admin			
        {
            ArcGIS_xFirewall Server_FirewallRules
            {
                Name                  = "ArcGISServer" 
                DisplayName           = "ArcGIS for Server" 
                DisplayGroup          = "ArcGIS for Server" 
                Ensure                = 'Present' 
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public") 
                LocalPort             = ("6443")                       
                Protocol              = "TCP" 
            }
            $Depends += '[ArcGIS_xFirewall]Server_FirewallRules'
        }   
        
        if($IsMultiMachineServer) 
        {
            $Depends += '[ArcGIS_xFirewall]Server_FirewallRules_Internal' 
            ArcGIS_xFirewall Server_FirewallRules_Internal
            {
                Name                  = "ArcGISServerInternal" 
                DisplayName           = "ArcGIS for Server Internal RMI" 
                DisplayGroup          = "ArcGIS for Server" 
                Ensure                = "Present" 
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public")
                LocalPort             = ("4000-4004")
                Protocol              = "TCP" 
            }

            if($ServerRole -ieq 'GeoAnalytics') 
            {  
                $Depends += '[ArcGIS_xFirewall]GeoAnalytics_InboundFirewallRules' 
                $Depends += '[ArcGIS_xFirewall]GeoAnalytics_OutboundFirewallRules' 

                ArcGIS_xFirewall GeoAnalytics_InboundFirewallRules
                {
                    Name                  = "ArcGISGeoAnalyticsInboundFirewallRules" 
                    DisplayName           = "ArcGIS GeoAnalytics" 
                    DisplayGroup          = "ArcGIS GeoAnalytics" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("2181","2182","2190","7077")	# Spark and Zookeeper
                    Protocol              = "TCP" 
                }

                ArcGIS_xFirewall GeoAnalytics_OutboundFirewallRules
                {
                    Name                  = "ArcGISGeoAnalyticsOutboundFirewallRules" 
                    DisplayName           = "ArcGIS GeoAnalytics" 
                    DisplayGroup          = "ArcGIS GeoAnalytics" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("2181","2182","2190","7077")	# Spark and Zookeeper
                    Protocol              = "TCP" 
                    Direction             = "Outbound"    
                }

                ArcGIS_xFirewall GeoAnalyticsCompute_InboundFirewallRules
                {
                    Name                  = "ArcGISGeoAnalyticsComputeInboundFirewallRules" 
                    DisplayName           = "ArcGIS GeoAnalytics" 
                    DisplayGroup          = "ArcGIS GeoAnalytics" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("56540-56550")	# GA Compute
                    Protocol              = "TCP" 
                }

                ArcGIS_xFirewall GeoAnalyticsCompute_OutboundFirewallRules
                {
                    Name                  = "ArcGISGeoAnalyticsComputeOutboundFirewallRules" 
                    DisplayName           = "ArcGIS GeoAnalytics" 
                    DisplayGroup          = "ArcGIS GeoAnalytics" 
                    Ensure                = 'Present'
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("56540-56550")	# GA Compute
                    Protocol              = "TCP" 
                    Direction             = "Outbound"    
                }
            }
        }

        ArcGIS_WindowsService ArcGIS_for_Server_Service
        {
            Name = 'ArcGIS Server'
            Credential = $ServiceCredential
            StartupType = 'Automatic'
            State = 'Running'
            DependsOn = $Depends
        }
        $Depends += '[ArcGIS_WindowsService]ArcGIS_for_Server_Service' 

        $DataDirs = @()
        if($null -ne $CloudStorageType){
            if(-not($CloudStorageType -ieq 'AzureFiles')){
                $DataDirs = @($ServerDirectoriesRootLocation)
                if($ServerDirectories -ne $null){
                    foreach($dir in $ServerDirectories){
                        $DataDirs += $dir.physicalPath
                    }
                }
            }
        }else{
            $DataDirs = @($ConfigStoreLocation,$ServerDirectoriesRootLocation) 
            if($ServerDirectories -ne $null){
                foreach($dir in $ServerDirectories){
                    $DataDirs += $dir.physicalPath
                }
            }
        }

        if($null -ne $ServerLogsLocation){
            $DataDirs += $ServerLogsLocation
        }

        if($null -ne $LocalRepositoryPath){
            $DataDirs += $LocalRepositoryPath
        }

        ArcGIS_Service_Account Server_RunAs_Account
        {
            Name = 'ArcGIS Server'
            RunAsAccount = $ServiceCredential
            Ensure = 'Present'
            DependsOn = $Depends
            DataDir = $DataDirs
            IsDomainAccount = $ServiceCredentialIsDomainAccount
        }

        $Depends += '[ArcGIS_Service_Account]Server_RunAs_Account' 

        if($AzureFilesEndpoint -and $CloudStorageCredentials -and ($CloudStorageType -ieq 'AzureFiles')) 
        {
            $filesStorageAccountName = $AzureFilesEndpoint.Substring(0, $AzureFilesEndpoint.IndexOf('.'))
            $storageAccountKey       = $CloudStorageCredentials.GetNetworkCredential().Password
    
            Script PersistStorageCredentials
            {
                TestScript = { 
                                $result = cmdkey "/list:$using:AzureFilesEndpoint"
                                $result | ForEach-Object{Write-verbose -Message "cmdkey: $_" -Verbose}
                                if($result -like '*none*')
                                {
                                    return $false
                                }
                                return $true
                        }
                SetScript = { 
                            $result = cmdkey "/add:$using:AzureFilesEndpoint" "/user:$using:filesStorageAccountName" "/pass:$using:storageAccountKey" 
                            $result | ForEach-Object{Write-verbose -Message "cmdkey: $_" -Verbose}
                        }
                GetScript            = { return @{} }                  
                DependsOn            = $Depends
                PsDscRunAsCredential = $ServiceCredential # This is critical, cmdkey must run as the service account to persist property
            }
            $Depends += '[Script]PersistStorageCredentials'
        } 

        if($Node.NodeName -ine $PrimaryServerMachine)
        {
            WaitForAll "WaitForAllServer$($PrimaryServerMachine)"{
                ResourceName = "[ArcGIS_Server]Server$($PrimaryServerMachine)"
                NodeName = $PrimaryServerMachine
                RetryIntervalSec = 60
                RetryCount = 100
                DependsOn = $Depends
            }
            $Depends += "[WaitForAll]WaitForAllServer$($PrimaryServerMachine)"
        }

        ArcGIS_Server "Server$($Node.NodeName)"
        {
            Ensure = 'Present'
            SiteAdministrator = $SiteAdministratorCredential
            ConfigurationStoreLocation = $ConfigStoreLocation
            ServerDirectoriesRootLocation = $ServerDirectoriesRootLocation
            ServerDirectories = (ConvertTo-JSON $ServerDirectories -Depth 5)
            ServerLogsLocation = $ServerLogsLocation
            LocalRepositoryPath = $LocalRepositoryPath
            Join =  if($Node.NodeName -ine $PrimaryServerMachine) { $true } else { $false } 
            PeerServerHostName = Get-FQDN $PrimaryServerMachine
            DependsOn = $Depends
            LogLevel = if($DebugMode) { 'DEBUG' } else { 'WARNING' }
            SingleClusterMode = $true
            ConfigStoreCloudStorageConnectionString = $ConfigStoreCloudStorageConnectionString
            ConfigStoreCloudStorageConnectionSecret = $ConfigStoreCloudStorageConnectionSecret
        }
        $Depends += "[ArcGIS_Server]Server$($Node.NodeName)"

        if($Node.SSLCertificate){
            ArcGIS_Server_TLS "Server_TLS_$($Node.NodeName)"
            {
                Ensure = 'Present'
                SiteName = 'arcgis'
                SiteAdministrator = $SiteAdministratorCredential                         
                CName =  $Node.SSLCertificate.CName
                CertificateFileLocation = $Node.SSLCertificate.Path
                CertificatePassword = $Node.SSLCertificate.Password
                EnableSSL = $True
                SslRootOrIntermediate = $SslRootOrIntermediate
                ServerType = "GeneralPurposeServer"
                DependsOn = $Depends
            }
            $Depends += "[ArcGIS_Server_TLS]Server_TLS_$($Node.NodeName)"
        }else{
            if(@("10.5.1").Contains($ConfigurationData.ConfigData.Version)){
                ArcGIS_Server_TLS "Server_TLS_$($Node.NodeName)"
                {
                    Ensure = 'Present'
                    SiteName = 'arcgis'
                    SiteAdministrator = $SiteAdministratorCredential                         
                    CName = $MachineFQDN
                    ServerType = "GeneralPurposeServer"
                    EnableSSL = $True
                    DependsOn = $Depends
                } 
                $Depends += "[ArcGIS_Server_TLS]Server_TLS_$($Node.NodeName)"
            }
        }
        
        if ($RegisteredDirectories -and ($Node.NodeName -ieq $PrimaryServerMachine)) {
            ArcGIS_Server_RegisterDirectories "Server$($Node.NodeName)RegisterDirectories"
            { 
                Ensure = 'Present'
                SiteAdministrator = $SiteAdministratorCredential
                DirectoriesJSON = $RegisteredDirectories
                DependsOn = $Depends
            }
            $Depends += "[ArcGIS_Server_RegisterDirectories]Server$($Node.NodeName)RegisterDirectories"
        }

        if($ServerRole -ieq "GeoEvent") 
        { 
            ArcGIS_Service_Account GeoEvent_RunAs_Account
            {
                Name = 'ArcGISGeoEvent'
                RunAsAccount = $ServiceCredential
                Ensure =  "Present"
                DependsOn = $Depends
                DataDir = "$env:ProgramData\Esri\GeoEvent"
                IsDomainAccount = $ServiceCredentialIsDomainAccount
            }

            $Depends += "[ArcGIS_Service_Account]GeoEvent_RunAs_Account"

            ArcGIS_WindowsService ArcGIS_GeoEvent_Service
            {
                Name = 'ArcGISGeoEvent'
                Credential = $ServiceCredential
                StartupType = 'Automatic'
                State = 'Running'
                DependsOn = $Depends
            }
            $Depends += "[ArcGIS_WindowsService]ArcGIS_GeoEvent_Service"

            ArcGIS_xFirewall GeoEvent_FirewallRules
            {
                Name                  = "ArcGISGeoEventFirewallRules" 
                DisplayName           = "ArcGIS GeoEvent" 
                DisplayGroup          = "ArcGIS GeoEvent" 
                Ensure                = "Present"
                Access                = "Allow" 
                State                 = "Enabled" 
                Profile               = ("Domain","Private","Public")
                LocalPort             = ("6143","6180","5565","5575")
                Protocol              = "TCP" 
                DependsOn             = $Depends
            }
            $Depends += "[ArcGIS_xFirewall]GeoEvent_FirewallRules"

            ArcGIS_GeoEvent ArcGIS_GeoEvent
            {
                Name	                  = 'ArcGIS GeoEvent'
                Ensure	                  =  "Present"
                SiteAdministrator         = $SiteAdministratorCredential
                WebSocketContextUrl       = "wss://$($MachineFQDN):6143/arcgis" #Fix this
                DependsOn                 = $Depends
                #SiteAdminUrl             = if($ConfigData.ExternalDNSName) { "https://$($ConfigData.ExternalDNSName)/arcgis/admin" } else { $null }
            }	
            $Depends += "[ArcGIS_xFirewall]GeoEvent_FirewallRules"
            
            if($IsMultiMachineServer) 
            {
                ArcGIS_xFirewall GeoEvent_FirewallRules_MultiMachine
                {
                    Name                  = "ArcGISGeoEventFirewallRulesCluster" 
                    DisplayName           = "ArcGIS GeoEvent Extension Cluster" 
                    DisplayGroup          = "ArcGIS GeoEvent Extension" 
                    Ensure                =  "Present"
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("2181","2182","2190","27271","27272","27273")										
                    Protocol              = "TCP" 
                    DependsOn             = $Depends
                }
                $Depends += "[ArcGIS_xFirewall]GeoEvent_FirewallRules_MultiMachine"

                ArcGIS_xFirewall GeoEvent_FirewallRules_MultiMachine_OutBound
                {
                    Name                  = "ArcGISGeoEventFirewallRulesClusterOutbound" 
                    DisplayName           = "ArcGIS GeoEvent Extension Cluster Outbound" 
                    DisplayGroup          = "ArcGIS GeoEvent Extension" 
                    Ensure                =  "Present"
                    Access                = "Allow" 
                    State                 = "Enabled" 
                    Profile               = ("Domain","Private","Public")
                    RemotePort            = ("2181","2182","2190","27271","27272","27273")										
                    Protocol              = "TCP" 
                    Direction             = "Outbound"    
                    DependsOn             = $Depends
                }
                $Depends += "[ArcGIS_xFirewall]GeoEvent_FirewallRules_MultiMachine_OutBound"
                ArcGIS_xFirewall GeoEventService_Firewall
                {
                    Name                  = "ArcGISGeoEventGateway"
                    DisplayName           = "ArcGIS GeoEvent Gateway"
                    DisplayGroup          = "ArcGIS GeoEvent Gateway"
                    Ensure                = 'Present'
                    Access                = "Allow"
                    State                 = "Enabled"
                    Profile               = ("Domain","Private","Public")
                    LocalPort             = ("9092")
                    Protocol              = "TCP"
                    DependsOn             = $Depends
                }
                $Depends += "[ArcGIS_xFirewall]GeoEventService_Firewall"
            }

            if(Get-Service 'ArcGISGeoEventGateway' -ErrorAction Ignore) 
            {
                ArcGIS_WindowsService ArcGIS_GeoEventGateway_Service
                {
                    Name		= 'ArcGISGeoEventGateway'
                    Credential  = $ServiceCredential
                    StartupType = 'Automatic'
                    State       = 'Running'
                    DependsOn   = $Depends
                }
                $Depends += "[ArcGIS_WindowsService]ArcGIS_GeoEventGateway_Service"
            }
        }
    }
}