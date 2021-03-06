Configuration ArcGISLicense 
{
    param(
        [System.Boolean]
        $ForceLicenseUpdate
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName @{ModuleName="ArcGIS";ModuleVersion="3.0.0"}
    Import-DscResource -Name ArcGIS_License

    Node $AllNodes.NodeName 
    {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }
        
        Foreach($NodeRole in $Node.Role)
        {
            Switch($NodeRole)
            {
                'Server'
                {
                    ArcGIS_License "ServerLicense$($Node.NodeName)"
                    {
                        LicenseFilePath =  $Node.ServerLicenseFilePath
                        LicensePassword = $Node.ServerLicensePassword
                        Ensure = "Present"
                        Component = 'Server'
                        ServerRole = $Node.ServerRole 
                        Force = $ForceLicenseUpdate
                    }
                }
                'Portal'
                {
                    ArcGIS_License "PortalLicense$($Node.NodeName)"
                    {
                        LicenseFilePath = $Node.PortalLicenseFilePath
                        LicensePassword = $Node.PortalLicensePassword
                        Ensure = "Present"
                        Component = 'Portal'
                        Force = $ForceLicenseUpdate
                    }                    
                }
                'Desktop'
                {
                    ArcGIS_License "DesktopLicense$($Node.NodeName)"
                    {
                        LicenseFilePath =  $Node.DesktopLicenseFilePath
                        LicensePassword = $null
                        IsSingleUse = $True
                        Ensure = "Present"
                        Component = 'Desktop'
                        Force = $ForceLicenseUpdate
                    }
                }
                'Pro' 
                {
                    ArcGIS_License "ProLicense$($Node.NodeName)"
                    {
                        LicenseFilePath =  $Node.ProLicenseFilePath
                        LicensePassword = $null
                        IsSingleUse = $True
                        Ensure = "Present"
                        Component = 'Pro'
                        Force = $ForceLicenseUpdate
                    }                
                }
                'LicenseManager'
                {   
                    if($Node.ProVersion -and $Node.ProLicenseFilePath){
                        ArcGIS_License "ProLicense$($Node.NodeName)"
                        {
                            LicenseFilePath = $Node.ProLicenseFilePath
                            LicensePassword = $null
                            Ensure = "Present"
                            Component = 'Pro'
                            Version = $Node.ProVersion 
                            Force = $ForceLicenseUpdate
                        }
                    }
                    if($Node.DesktopVersion -and $Node.DesktopLicenseFilePath){
                        ArcGIS_License "DesktopLicense$($Node.NodeName)"
                        {
                            LicenseFilePath = $Node.DesktopLicenseFilePath
                            LicensePassword = $null
                            Ensure = "Present"
                            Component = 'Desktop'
                            Version = $Node.DesktopVersion
                            Force = $ForceLicenseUpdate
                        }
                    }
                }
            }
        }
    }
}