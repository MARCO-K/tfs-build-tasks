function CreateDataContent()
{
    #System.Net.Http.HttpContent
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Name,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Value
    )
		$contentDispositionHeaderValue = New-Object -TypeName  System.Net.Http.Headers.ContentDispositionHeaderValue -ArgumentList @("form-data")
	    $contentDispositionHeaderValue.Name = $Name

        $content = New-Object -TypeName System.Net.Http.StringContent -ArgumentList @($Value)
        $content.Headers.ContentDisposition = $contentDispositionHeaderValue

        return $content
}

function Import-Artifact()
{
    [CmdletBinding()]
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$EndpointUrl,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Repository,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Group,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Artifact,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Version,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Packaging,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PackagePath,
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential
    )
    BEGIN
    {
        if (-not (Test-Path $PackagePath))
        {
            $errorMessage = ("Package file {0} missing or unable to read." -f $packagePath)
            $exception =  New-Object System.Exception $errorMessage
			$errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, 'XLDPkgUpload', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $packagePath
			$PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
    PROCESS
    {
        $fileName = Split-Path $packagePath -leaf
        $fileName = Get-EncodedPathPart($fileName) 

        Add-Type -AssemblyName System.Net.Http

        $networkCredential = New-Object -TypeName System.Net.NetworkCredential -ArgumentList @($Credential.UserName, $Credential.Password)
		$httpClientHandler = New-Object -TypeName System.Net.Http.HttpClientHandler
		$httpClientHandler.Credentials = $networkCredential

        $repoContent = CreateDataContent "r" $Repository
        $groupContent = CreateDataContent "g" $Group
        $artifactContent = CreateDataContent "a" $Artifact
        $versionContent = CreateDataContent "v" $Version
        $packagingContent = CreateDataContent "p" $Packaging

        $content = New-Object -TypeName System.Net.Http.MultipartFormDataContent
        $content.Add($repoContent)
        $content.Add($groupContent)
        $content.Add($artifactContent)
        $content.Add($versionContent)
        $content.Add($packagingContent)


    }
    END
    {

    }
}



function Send-Package()
{
    [CmdletBinding()]
    param
    (
        [string][parameter(Mandatory = $true, ValueFromPipeline = $true)][ValidateNotNullOrEmpty()]$packagePath,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$EndpointUrl,
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential
    )
    BEGIN
    {
        Write-Verbose "packagePath = $packagePath"
        Write-Verbose "XldServerUrl = $EndpointUrl"
        Write-Verbose "XldServerCredentials Username = $($Credential.UserName)"
    }
    PROCESS
    {
        if (-not (Test-Path $packagePath))
        {
            $errorMessage = ("Package file {0} missing or unable to read." -f $packagePath)
            $exception =  New-Object System.Exception $errorMessage
			$errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, 'XLDPkgUpload', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $packagePath
			$PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        $fileName = Split-Path $packagePath -leaf
        $fileName = Get-EncodedPathPart($fileName) 

        Add-Type -AssemblyName System.Net.Http

		$networkCredential = New-Object -TypeName System.Net.NetworkCredential -ArgumentList @($Credential.UserName, $Credential.Password)
		$httpClientHandler = New-Object -TypeName System.Net.Http.HttpClientHandler
		$httpClientHandler.Credentials = $networkCredential

        $httpClient = New-Object -TypeName System.Net.Http.Httpclient -ArgumentList @($httpClientHandler)

        $packageFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList @($packagePath, [System.IO.FileMode]::Open)
        
		$contentDispositionHeaderValue = New-Object -TypeName  System.Net.Http.Headers.ContentDispositionHeaderValue -ArgumentList @("form-data")
	    $contentDispositionHeaderValue.Name = "fileData"
		$contentDispositionHeaderValue.FileName = $fileName

        $streamContent = New-Object -TypeName System.Net.Http.StreamContent -ArgumentList @($packageFileStream)
        $streamContent.Headers.ContentDisposition = $contentDispositionHeaderValue
        $streamContent.Headers.ContentType = New-Object -TypeName System.Net.Http.Headers.MediaTypeHeaderValue -ArgumentList @("application/octet-stream")
        
        $content = New-Object -TypeName System.Net.Http.MultipartFormDataContent
        $content.Add($streamContent)

        try
        {
			$response = $httpClient.PostAsync("$EndpointUrl/package/upload/$fileName", $content).Result

			if (!$response.IsSuccessStatusCode)
			{
				$responseBody = $response.Content.ReadAsStringAsync().Result
				$errorMessage = "Status code {0}. Reason {1}. Server reported the following message: {2}." -f $response.StatusCode, $response.ReasonPhrase, $responseBody

				throw [System.Net.Http.HttpRequestException] $errorMessage
			}

			$responseBody = [xml]$response.Content.ReadAsStringAsync().Result

            return $responseBody.'udm.DeploymentPackage'.id
        }
        catch [Exception]
        {
			$PSCmdlet.ThrowTerminatingError($_)
        }
        finally
        {
            if($null -ne $httpClient)
            {
                $httpClient.Dispose()
            }

            if($null -ne $response)
            {
                $response.Dispose()
            }
        }
    }
    END { }
}