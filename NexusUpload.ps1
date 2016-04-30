function CreateStringContent()
{
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Name,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Value,
        [string]$FileName,
        [string]$MediaTypeHeaderValue
    )
		$contentDispositionHeaderValue = New-Object -TypeName  System.Net.Http.Headers.ContentDispositionHeaderValue -ArgumentList @("form-data")
	    $contentDispositionHeaderValue.Name = $Name

        if ($FileName)
        {
            $contentDispositionHeaderValue.FileName = $FileName
        }
        
        $content = New-Object -TypeName System.Net.Http.StringContent -ArgumentList @($Value)
        $content.Headers.ContentDisposition = $contentDispositionHeaderValue

        if ($MediaTypeHeaderValue)
        {
            $content.Headers.ContentType = New-Object -TypeName System.Net.Http.Headers.MediaTypeHeaderValue $MediaTypeHeaderValue
        }

        return $content
}

function CreateStreamContent()
{
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PackagePath
    )
        $packageFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList @($PackagePath, [System.IO.FileMode]::Open)
        
		$contentDispositionHeaderValue = New-Object -TypeName  System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
	    $contentDispositionHeaderValue.Name = "file"
		$contentDispositionHeaderValue.FileName = Split-Path $packagePath -leaf

        $streamContent = New-Object -TypeName System.Net.Http.StreamContent $packageFileStream
        $streamContent.Headers.ContentDisposition = $contentDispositionHeaderValue
        $streamContent.Headers.ContentType = New-Object -TypeName System.Net.Http.Headers.MediaTypeHeaderValue "application/octet-stream"

        return $streamContent
}

function GetHttpClientHandler()
{
    param
    (
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential
    )

    $networkCredential = New-Object -TypeName System.Net.NetworkCredential -ArgumentList @($Credential.UserName, $Credential.Password)
	$httpClientHandler = New-Object -TypeName System.Net.Http.HttpClientHandler
	$httpClientHandler.Credentials = $networkCredential

    return $httpClientHandler
}

function PostArtifact()
{
    param
    (
        [string][parameter(Mandatory = $true)]$EndpointUrl,
        [System.Net.Http.HttpClientHandler][parameter(Mandatory = $true)]$Handler,
        [System.Net.Http.HttpContent][parameter(Mandatory = $true)]$Content
    )

    $httpClient = New-Object -TypeName System.Net.Http.Httpclient $Handler

    try
    {
		$response = $httpClient.PostAsync("$EndpointUrl/service/local/artifact/maven/content", $Content).Result

		if (!$response.IsSuccessStatusCode)
		{
			$responseBody = $response.Content.ReadAsStringAsync().Result
			$errorMessage = "Status code {0}. Reason {1}. Server reported the following message: {2}." -f $response.StatusCode, $response.ReasonPhrase, $responseBody

			throw [System.Net.Http.HttpRequestException] $errorMessage
		}

		return $response.Content.ReadAsStringAsync().Result
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

function Import-ArtifactGAV()
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

        Add-Type -AssemblyName System.Net.Http
    }
    PROCESS
    {
        $repoContent = CreateStringContent "r" $Repository
        $groupContent = CreateStringContent "g" $Group
        $artifactContent = CreateStringContent "a" $Artifact
        $versionContent = CreateStringContent "v" $Version
        $packagingContent = CreateStringContent "p" $Packaging
        $streamContent = CreateStreamContent $PackagePath

        $content = New-Object -TypeName System.Net.Http.MultipartFormDataContent
        $content.Add($repoContent)
        $content.Add($groupContent)
        $content.Add($artifactContent)
        $content.Add($versionContent)
        $content.Add($packagingContent)
        $content.Add($streamContent)

        $httpClientHandler = GetHttpClientHandler $Credential

        return PostArtifact $EndpointUrl $httpClientHandler $content
    }
    END { }
}

function Import-ArtifactPOM()
{
    [CmdletBinding()]
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$EndpointUrl,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Repository,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PomFilePath,
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PackagePath,
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential
    )
    BEGIN
    {
        if (-not (Test-Path $PackagePath))
        {
            $errorMessage = ("Package file {0} missing or unable to read." -f $PackagePath)
            $exception =  New-Object System.Exception $errorMessage
			$errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, 'ArtifactUpload', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $PackagePath
			$PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        
        if (-not (Test-Path $PomFilePath))
        {
            $errorMessage = ("POM file {0} missing or unable to read." -f $PomFilePath)
            $exception =  New-Object System.Exception $errorMessage
			$errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, 'ArtifactUpload', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $PomFilePath
			$PSCmdlet.ThrowTerminatingError($errorRecord)
        }

        Add-Type -AssemblyName System.Net.Http
    }
    PROCESS
    {
        $repoContent = CreateStringContent "r" $Repository
        $groupContent = CreateStringContent "hasPom" "true"
        $pomContent = CreateStringContent "file" "$(Get-Content $PomFilePath)" ([system.IO.Path]::GetFileName($PomFilePath)) "text/xml"
        $streamContent = CreateStreamContent $PackagePath

        $content = New-Object -TypeName System.Net.Http.MultipartFormDataContent
        $content.Add($repoContent)
        $content.Add($groupContent)
        $content.Add($pomContent)
        $content.Add($streamContent)

        $httpClientHandler = GetHttpClientHandler $Credential

        return PostArtifact $EndpointUrl $httpClientHandler $content
    }
    END { }
}

$server = "http://nexus.eu.rabodev.com"
$credential = Get-Credential
$pomFile = "C:\Users\majcicam\Desktop\pom.xml"
$package = "C:\Users\majcicam\Downloads\curl-7.45.0\AMD64\junit-4.12.jar"

Import-ArtifactGAV $server "maven" "com.test" "project" "2.3" "jar" $package $credential
Import-ArtifactPOM $server "maven" $pomFile $package $credential
