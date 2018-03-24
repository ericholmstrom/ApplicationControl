# Requires -Version 2
Function New-AcAampConfiguration {
    <#
        .SYNOPSIS
          Creates an Ivanti Application Control configuration from an array of inputs.
            
        .DESCRIPTION
          Works with Get-DigitalSignatures and Get-FileMetadata to create an Ivanti Application Control configuration.
          Intended for making it easier to define an application and create a rule set automatically for copying into a detailed configuration.
  
          Adds Accessible files and Accessible folders with metadata and Trusted Vendor certificates to the Everyone group rule.
  
        .NOTES
          Author: Aaron Parker
          Twitter: @stealthpuppy
  
        .LINK
          https://github.com/Insentra/ApplicationControl
  
        .OUTPUTS
          [System.String]
  
        .PARAMETER AccessibleFiles
            An array of files with metadata to add to the Allowed list.

        .PARAMETER TrustedVendors
            An array of signed files for extracting the certificate to add to the Trusted Vendors list.
        
        .PARAMETER RegEx
            For AccessibleFiles, treat the paths as RegEx.

        .PARAMETER GroupRule
            The Group rule to add the AccessibleFiles and TrustedVendors to. Defaults to Everyone.

        .PARAMETER Path
            A full file path to output the temporary Application Control configuration to. Defaults to C:\Temp\Configuration.aamp
        
        .PARAMETER IgnoreCRL
            Enable or disable ignore CRL flags for Trusted Vendor certificates. Typically CRL checking is an issue behind a proxy server.
  
        .EXAMPLE
          New-AampConfiguration -AccessibleFiles $Files -Path "C:\Temp\Configuration.aamp"
  
          Description:
          Adds files and metadata in the array $Files to a new Application Control configuration at "C:\Temp\Configuration.aamp".

        .EXAMPLE
          New-AampConfiguration -AccessibleFiles $Files -RegEx
  
          Description:
          Adds files and metadata in the array $Files to a new Application Control configuration at the default path of "C:\Temp\Configuration.aamp". With file paths treated as RegEx.

        .EXAMPLE
          New-AampConfiguration -TrustedVendors $SignedFiles -Path "C:\Temp\Configuration.aamp"
  
          Description:
          Adds Trusted Vendor certificates from the files in the array $SignedFiles to a new Application Control configuration at "C:\Temp\Configuration.aamp".
#>
    [CmdletBinding(SupportsShouldProcess = $False)]
    Param (
        [Parameter(Mandatory = $False, Position = 0, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $False, `
                HelpMessage = 'Specify the array of accessible files with metadata to add.')]
        [array]$AccessibleFiles,

        [Parameter(Mandatory = $False, Position = 1, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False, `
                HelpMessage = 'Specify a target file or files that have been signed.')]
        [array]$TrustedVendors,

        [Parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False, `
                HelpMessage = 'Treat paths as RegEx.')]
        [switch]$RegEx,

        [Parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False, `
                HelpMessage = 'Specify the rule name to add the items to.')]
        [string]$GroupRule = "Everyone",

        [Parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False, `
                HelpMessage = 'Specify a path to the configuration to output.')]
        [string]$Path = "C:\Temp\Configuration.aamp",

        [Parameter(Mandatory = $False, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False, `
        HelpMessage = 'Enable or disable ignore CRL flags for Trusted Vendor certificates.')]
        [boolean]$IgnoreCRL = $True
    )
    Begin {  
        # Create the configuration; Create the configuration helper
        Try {
            Write-Verbose "Loading object 'AM.Configuration.5'."
            $Configuration = New-Object -ComObject 'AM.Configuration.5' -ErrorAction SilentlyContinue
        }
        Catch {
            Throw "Unable to load COM Object 'AM.Configuration.5'"
        }
        Try {
            Write-Verbose "Loading object 'AM.ConfigurationHelper.1'."
            $ConfigurationHelper = New-Object -ComObject 'AM.ConfigurationHelper.1' -ErrorAction SilentlyContinue
        }
        Catch {
            Throw "Unable to load COM Object 'AM.ConfigurationHelper.1'"
        }

        # Create configuration objects
        If ($PSBoundParameters.ContainsKey('AccessibleFiles')) {
            Write-Verbose "Creating AM.File instance"
            $AccessibleFile = $Configuration.CreateInstanceFromClassName("AM.File")
        }
        If ($PSBoundParameters.ContainsKey('TrustedVendors')) {
            Write-Verbose "Creating AM.DigitalCertificate instance"
            $DigitalCertificate = $Configuration.CreateInstanceFromClassName("AM.DigitalCertificate")
        }

        # Create default configuration
        Write-Verbose "Creating Application Control default configuration"
        $ConfigurationXml = $ConfigurationHelper.DefaultConfiguration
        $Configuration.ParseXML($ConfigurationXml)

        # Remove the default folders from the configuration to make viewing the config simpler
        Write-Verbose "Removing default folders from the configuration in rule $GroupRule."
        ForEach ($folder in $Configuration.GroupRules.Item($GroupRule).AccessibleFolders) {
            $Configuration.GroupRules.Item($GroupRule).AccessibleFolders.Remove($folder.Path) | Out-Null
        }

        # RegEx to grab CN from certificates
        $FindCN = "(?:.*CN=)(.*?)(?:,\ O.*)"
    }
    Process {
        If ($PSBoundParameters.ContainsKey('AccessibleFiles')) {
            ForEach ($file in $AccessibleFiles) {
                # Add a file to the list of accessible files.
                Write-Verbose "[Adding Accessible File] $(ConvertTo-EnvironmentPath -Path $file.Path)"
                $AccessibleFile.Path = $(ConvertTo-EnvironmentPath -Path $file.Path)
                If ($RegEx) {
                    $AccessibleFile.UseRegularExpression = $True
                    # Make CommandLine unique because this is the file entry key value
                    $AccessibleFile.CommandLine = "$($file.Path) $(([guid]::NewGuid()).ToString())"
                } Else {
                    $AccessibleFile.CommandLine = $(ConvertTo-EnvironmentPath -Path $file.Path)
                }
                $AccessibleFile.TrustedOwnershipChecking = $False
                # Filter on metadata greater than a single character. Some files have metadata fields with a single space
                If ($file.Company -gt 1) {
                    $AccessibleFile.Metadata.CompanyName = $file.Company
                    $AccessibleFile.Metadata.CompanyNameEnabled = $True
                    $AccessibleFile.Description = $file.Company
                } Else {
                    $AccessibleFile.Metadata.CompanyNameEnabled = $False
                }
                If ($file.Vendor -gt 1) {
                    $AccessibleFile.Metadata.VendorName = $file.Vendor
                    $AccessibleFile.Metadata.VendorNameEnabled = $True
                    $AccessibleFile.Description = $file.Vendor
                } Else {
                    $AccessibleFile.Metadata.VendorNameEnabled = $False
                }
                If ($file.Product -gt 1) {
                    $AccessibleFile.Metadata.ProductName = $file.Product
                    $AccessibleFile.Metadata.ProductNameEnabled = $True
                    $AccessibleFile.Description = $file.Product
                } Else {
                    $AccessibleFile.Metadata.ProductNameEnabled = $False
                }
                If ($file.Description -gt 1) {
                    $AccessibleFile.Metadata.FileDescription = $file.Description
                    $AccessibleFile.Metadata.FileDescriptionEnabled = $True
                    $AccessibleFile.Description = $file.Description
                } Else {
                    $AccessibleFile.Metadata.FileDescriptionEnabled = $False
                }
                If (!($AccessibleFile.Description)) {
                    $AccessibleFile.Description = "[No metadata found]"
                }

                # Add file to the rule and remove values from all properties ready for next file
                $Configuration.GroupRules.Item($GroupRule).AccessibleFiles.Add($AccessibleFile.Xml()) | Out-Null
                $AccessibleFile.Path = ""
                $AccessibleFile.CommandLine = ""
                $AccessibleFile.Description = ""
                $AccessibleFile.Metadata.CompanyName = ""
                $AccessibleFile.Metadata.VendorName = ""
                $AccessibleFile.Metadata.ProductName = ""
                $AccessibleFile.Metadata.FileDescription = ""
            }
        }

        If ($PSBoundParameters.ContainsKey('TrustedVendors')) {
            ForEach ($File in $TrustedVendors) {
                # Adding Trusted Vendors
                Write-Verbose "[Adding Trusted Vendor]"
                # Use the helper object to read the certificate and expiry date from the signed file
                [ref]$dtMyDate = New-Object System.Object
                Write-Verbose "Reading certificate from $($File.Path)"
                $CertificateData = $ConfigurationHelper.ReadCertificateDateFromFile($File.Path, 0, $dtMyDate)

                # Get details from the certificate for Issuer and Subject
                # Could look at simplifying reading the certificate by using X509Certificate2 instead of AM.ConfigurationHelper.1
                $CertObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $CertObj.Import($File.Path)

                # Build Trusted Vendor certificate; Add the certificate information to the configuration
                Write-Verbose "Certificate: $($CertObj.Subject); $($dtMyDate.Value.ToShortDateString()) $($dtMyDate.Value.ToShortTimeString())"
                $DigitalCertificate.RawCertificateData = $CertificateData
                Write-Verbose "Issuer: $($CertObj.Issuer)"
                $DigitalCertificate.Description = "Issuer: $($CertObj.Issuer -replace $FindCN, '$1'). Thumbprint: $($CertObj.Thumbprint)"
                $DigitalCertificate.IssuedTo = ($CertObj.Subject -replace $FindCN, '$1') -replace '"', ""
                $DigitalCertificate.ExpiryDate = "$($dtMyDate.Value.ToShortDateString()) $($dtMyDate.Value.ToShortTimeString())"
                If ($IgnoreCRL) {
                    # Enable 'Ignore end Certificate revocation errors' - remove if no issue with CRL checking.
                    # Typically CRL checking is an issue behind a proxy server
                    $DigitalCertificate.ErrorIgnoreFlags = 1792
                }
                $Configuration.GroupRules.Item($GroupRule).TrustedVendors.Add($DigitalCertificate.Xml()) | Out-Null
            }
        }
    }
    End {
        # Save the configuration and output the path to it
        If (!(Test-Path -Path (Split-Path -Path $Path -Parent))) {
            Write-Verbose "Creating folder $(Split-Path -Path $Path -Parent)"
            New-Item -Path (Split-Path -Path $Path -Parent) -ItemType Directory | Out-Null
        }
        Write-Verbose "Saving configuration to: $Path"
        $ConfigurationHelper.SaveLocalConfiguration($Path, $Configuration.Xml())
        $Path
    }
}