Param (
    [string]$SourcesDirectory,
    [string]$ProductName,
    [int]$MajorVersion,
    [int]$MinorVersion,
    [int]$PatchVersion,
    [string]$PrereleaseLabel = $null,
    [int]$AssemblyFileVersionRevisionOverride,
    [int]$PackagePrereleaseRevisionOverride
)

function StampVersionsInAssemblyInfoFile
{
    Param (
        [string]$AssemblyInfoFile,
        [string]$AssemblyVersion,
        [string]$AssemblyFileVersion,
        [string]$AssemblyInformationalVersion
    )

    [string]$originalFile = [System.IO.File]::ReadAllText($AssemblyInfoFile);

    [string]$assemblyVersionRegex = "(?<firstPart>\[([^\]]*)AssemblyVersion(Attribute)?[\s]*\([\s]*`")(?<version>[^`"]*)(?<lastPart>`"[\s]*\)[\s]*\])";
    [string]$assemblyFileVersionRegex = "(?<firstPart>\[([^\]]*)AssemblyFileVersion(Attribute)?[\s]*\([\s]*`")(?<version>[^`"]*)(?<lastPart>`"[\s]*\)[\s]*\])";
    [string]$assemblyInformationalVersionRegex = "(?<firstPart>\[([^\]]*)AssemblyInformationalVersion(Attribute)?[\s]*\([\s]*`")(?<version>[^`"]*)(?<lastPart>`"[\s]*\)[\s]*\])";
    
    [string]$newFile = [System.Text.RegularExpressions.Regex]::Replace($originalFile, $assemblyVersionRegex, '${firstPart}' + $AssemblyVersion + '${lastPart}');
    $newFile = [System.Text.RegularExpressions.Regex]::Replace($newFile, $assemblyFileVersionRegex, '${firstPart}' + $AssemblyFileVersion + '${lastPart}');
    $newFile = [System.Text.RegularExpressions.Regex]::Replace($newFile, $assemblyInformationalVersionRegex, '${firstPart}' + $AssemblyInformationalVersion + '${lastPart}');

    if ($newFile -ne $originalFile)
    {
        [System.IO.File]::WriteAllText($AssemblyInfoFile, $newFile);
        Write-Host "Version numbers updated in '$AssemblyInfoFile'.";
        $true;
    }
    else
    {
        $false;
    }
}

function StampVersionsInNetstandardCsprojFile
{
    Param (
        [string]$CsprojFile,
        [string]$AssemblyVersion,
        [string]$AssemblyFileVersion,
        [string]$AssemblyInformationalVersion,
        [string]$AssemblyInformationalVersionSuffix
    )

    [string]$originalXml = [System.IO.File]::ReadAllText($CsprojFile);

    $xml = New-Object System.Xml.XmlDocument;
    $xml.PreserveWhitespace = $true;
    $xml.LoadXml($originalXml);

    # Set /Project/PropertyGroup/Version elements to $AssemblyInformationalVersion
    $versionNodes = $xml.SelectNodes("/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'Version']");
    foreach ($versionNode in $versionNodes)
    {
        $versionNode.InnerText = $AssemblyInformationalVersion;
    }

    # Set /Project/PropertyGroup/VersionPrefix elements to $AssemblyVersion
    $versionNodes = $xml.SelectNodes("/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'VersionPrefix']");
    foreach ($versionNode in $versionNodes)
    {
        $versionNode.InnerText = $AssemblyVersion;
    }

    # Set /Project/PropertyGroup/VersionSuffix elements to $AssemblyInformationalVersionSuffix
    $versionNodes = $xml.SelectNodes("/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'VersionSuffix']");
    foreach ($versionNode in $versionNodes)
    {
        $versionNode.InnerText = $AssemblyInformationalVersionSuffix;
    }

    # Set /Project/PropertyGroup/FileVersion elements to $AssemblyFileVersion
    $versionNodes = $xml.SelectNodes("/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'FileVersion']");
    foreach ($versionNode in $versionNodes)
    {
        $versionNode.InnerText = $AssemblyFileVersion;
    }

    [string]$newXml = $xml.OuterXml;

    if ($newXml -ne $originalXml)
    {
        [System.IO.File]::WriteAllText($CsprojFile, $newXml);
        Write-Host "Version numbers updated in '$CsprojFile'.";
        $true;
    }
    else
    {
        $false;
    }
}

function StampVersionsInNuSpecFile
{
    Param (
        [string]$NuspecFile,
        [string]$Version
    )

    [string]$originalFile = [System.IO.File]::ReadAllText($NuspecFile);

    [string]$versionRegex = "<version>(?<version>[^\<]*)</version>";
    
    [string]$newFile = [System.Text.RegularExpressions.Regex]::Replace($originalFile, $versionRegex, "<version>$Version</version>");

    if ($newFile -ne $originalFile)
    {
        [System.IO.File]::WriteAllText($NuspecFile, $newFile);
        Write-Host "Version numbers updated in '$NuspecFile'.";
        $true;
    }
    else
    {
        $false;
    }
}

function StampVersionsInVsixmanifestFile
{
    Param (
        [string]$VsixmanifestFile,
        [string]$Version
    )

    [string]$originalXml = [System.IO.File]::ReadAllText($VsixmanifestFile);

    $xml = New-Object System.Xml.XmlDocument;
    $xml.PreserveWhitespace = $true;
    $xml.LoadXml($originalXml);

    $identityNodes = $xml.SelectNodes("/*[local-name() = 'PackageManifest']/*[local-name() = 'Metadata']/*[local-name() = 'Identity']");
    foreach ($identityNode in $identityNodes)
    {
        $identityNode.SetAttribute("Version", $Version);
    }

    [string]$newXml = $xml.OuterXml;

    if ($newFile -ne $originalXml)
    {
        [System.IO.File]::WriteAllText($VsixmanifestFile, $newXml);
        Write-Host "Version numbers updated in '$VsixmanifestFile'.";
        $true;
    }
    else
    {
        $false;
    }
}

function StampVersions
{
    Param (
        [string]$Directory,
        [string]$AssemblyVersion,
        [string]$AssemblyFileVersion,
        [string]$AssemblyInformationalVersion,
        [string]$AssemblyInformationalVersionSuffix
    )

    Write-Host "Searching for files in '$Directory' to stamp version info in...";

    [bool]$wereAnyFilesUpdated = $false;

    # Update *AssemblyInfo.cs files
    foreach ($assemblyInfoFile in [System.IO.Directory]::EnumerateFiles($Directory, "*AssemblyInfo.cs", [System.IO.SearchOption]::AllDirectories))
    {
        [bool]$wasFileUpdated = StampVersionsInAssemblyInfoFile -AssemblyInfoFile $assemblyInfoFile -AssemblyVersion $AssemblyVersion -AssemblyFileVersion $AssemblyFileVersion -AssemblyInformationalVersion $AssemblyInformationalVersion;
        $wereAnyFilesUpdated = $wereAnyFilesUpdated -or $wasFileUpdated;
    }

    # Update *.csproj files
    foreach ($csprojFile in [System.IO.Directory]::EnumerateFiles($Directory, "*.csproj", [System.IO.SearchOption]::AllDirectories))
    {
        [bool]$wasFileUpdated = StampVersionsInNetstandardCsprojFile -CsprojFile $csprojFile -AssemblyVersion $AssemblyVersion -AssemblyFileVersion $AssemblyFileVersion -AssemblyInformationalVersion $AssemblyInformationalVersion -AssemblyInformationalVersionSuffix $AssemblyInformationalVersionSuffix;
        $wereAnyFilesUpdated = $wereAnyFilesUpdated -or $wasFileUpdated;
    }

    # Update *.nuspec files
    foreach ($nuspecFile in [System.IO.Directory]::EnumerateFiles($Directory, "*.nuspec", [System.IO.SearchOption]::AllDirectories))
    {
        [bool]$wasFileUpdated = StampVersionsInNuspecFile -NuspecFile $nuspecFile -Version $AssemblyInformationalVersion;
        $wereAnyFilesUpdated = $wereAnyFilesUpdated -or $wasFileUpdated;
    }

    # Update *.vsixmanifest files
    foreach ($vsixmanifestFile in [System.IO.Directory]::EnumerateFiles($Directory, "*.vsixmanifest", [System.IO.SearchOption]::AllDirectories))
    {
        [bool]$wasFileUpdated = StampVersionsInVsixmanifestFile -VsixmanifestFile $vsixmanifestFile -Version $AssemblyFileVersion;
        $wereAnyFilesUpdated = $wereAnyFilesUpdated -or $wasFileUpdated;
    }

    if (!$wereAnyFilesUpdated)
    {
        Write-Host "##vso[task.logissue type=warning;]WARNING: No files were updated.";
    }
}

function CreateOrIncrementRevision
{
    Param (
        [string]$ProductName,
        [string]$RevisionKey,
        [int]$RevisionOverride
        )

    if ([System.String]::IsNullOrWhiteSpace($env:SYSTEM_ACCESSTOKEN))
    {
        Write-Host "##vso[task.logissue type=error]ERROR: The Stamp Version Information build task requires access to the OAuth token to store revision numbers. Please enable the 'Allow Scripts to Access OAuth Token' option for this build definition.";
        Write-Host "##vso[task.complete result=Failed]DONE";
        Exit;
    }

    [string]$extmgmtBaseUrlRegex = "(?<firstPart>https?:\/\/.+)(?<lastPart>\.visualstudio\.com.*)";
    [string]$extmgmtBaseUrl = [System.Text.RegularExpressions.Regex]::Replace($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI, $extmgmtBaseUrlRegex, '${firstPart}' + '.extmgmt' + '${lastPart}');

    [int]$maxAttempts = 5;
    [int]$attempt = 1;

    [string]$urlEncodedProductName = [System.Web.HttpUtility]::UrlEncode($ProductName);
    [string]$urlEncodedRevisionKey = [System.Web.HttpUtility]::UrlEncode($RevisionKey);

    # Make up to 5 attempts to create or update the revision
    while ($attempts -le $maxAttempts)
    {
        [System.Net.Http.HttpClient]$httpClient = $null;
        [System.Net.Http.HttpResponseMessage]$getResponse = $null;
        [System.Net.Http.HttpResponseMessage]$setResponse = $null;

        try
        {
            $httpClient = New-Object System.Net.Http.HttpClient;
            $httpClient.BaseAddress = $extmgmtBaseUrl;
            $httpClient.DefaultRequestHeaders.Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN";
            [void]$httpClient.DefaultRequestHeaders.Accept.Add("application/json; api-version=3.1-preview.1");

            Write-Host "Attempting to get the current revision for '$RevisionKey' of '$ProductName'...";
            
            [string]$getUrl = "_apis/ExtensionManagement/InstalledExtensions/csdahlberg/versioning/Data/Scopes/Default/Current/Collections/Revisions/Documents/$urlEncodedProductName";
            $getResponse = $httpClient.GetAsync($getUrl).GetAwaiter().GetResult();

            if ($getResponse.StatusCode -eq [System.Net.HttpStatusCode]::OK)
            {
                # The product has existing revision information, so it needs to be updated

                $revisionInformation = $getResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json;

                if ($revisionInformation.PSObject.Properties.Name -contains $urlEncodedRevisionKey)
                {
                    # The version has a revision set for it, so it will be updated

                    [int]$currentRevision = $revisionInformation.$urlEncodedRevisionKey;
                    if ($RevisionOverride -lt 0)
                    {
                        [int]$newRevision = $currentRevision + 1;
                        $revisionInformation.$urlEncodedRevisionKey = $newRevision;
                        Write-Host "A revision of '$currentRevision' already exists for '$RevisionKey'. Incrementing it to '$newRevision'...";
                    }
                    else
                    {
                        $revisionInformation.$urlEncodedRevisionKey = $RevisionOverride;
                        Write-Host "A revision of '$currentRevision' already exists for '$RevisionKey'. Setting it to the override value of '$RevisionOverride'...";
                    }
                }
                else
                {
                    # The version does not have a revision set for it, so it will be created.

                    if ($RevisionOverride -lt 0)
                    {
                        $revisionInformation | Add-Member -Name $urlEncodedRevisionKey -MemberType NoteProperty -Value 1;
                        Write-Host "A revision of '1' will be created for '$RevisionKey'.";
                    }
                    else
                    {
                        $revisionInformation | Add-Member -Name $urlEncodedRevisionKey -MemberType NoteProperty -Value $RevisionOverride;
                        Write-Host "A revision of the override value '$RevisionOverride' will be created for '$RevisionKey'.";
                    }
                }

                [string]$setRequestJson = $revisionInformation | ConvertTo-Json;

                [System.Net.Http.StringContent]$setRequestContent = New-Object System.Net.Http.StringContent($setRequestJson);
                $setRequestContent.Headers.ContentType = "application/json";

                [string]$setUrl = "_apis/ExtensionManagement/InstalledExtensions/csdahlberg/versioning/Data/Scopes/Default/Current/Collections/Revisions/Documents";
                $setResponse = $httpClient.PutAsync($setUrl, $setRequestContent).GetAwaiter().GetResult();

                if ($setResponse.IsSuccessStatusCode)
                {
                    $revisionInformation.$urlEncodedRevisionKey;
                    return;
                }

                # If the value was modified by some other process, the __etag value won't be valid and a BadRequest status will be returned with a typeKey value of "InvalidDocumentVersionException" in the response body.
                if ($setResponse.StatusCode -eq [System.Net.HttpStatusCode]::BadRequest)
                {
                    $setResponseJson = $setResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                    $setResponseObject = $setResponseJson | ConvertFrom-Json;
                    if ($setResponseObject.typeKey -eq "InvalidDocumentVersionException")
                    {
                        Write-Host "Saving the new revision for '$RevisionKey' failed, probably because it was modified by another process.";
                    }
                    else
                    {
                        Write-Host "##vso[task.logissue type=error]ERROR: An error was returned attempting to increment the current revision for '$RevisionKey': $setResponse";
                        Write-Host "##vso[task.complete result=Failed]DONE";
                        Exit;
                    }
                }
                else
                {
                    Write-Host "##vso[task.logissue type=error]ERROR: An error was returned attempting to increment the current revision for '$RevisionKey': $setResponse";
                    Write-Host "##vso[task.complete result=Failed]DONE";
                    Exit;
                }
            }
            elseif ($getResponse.StatusCode -eq [System.Net.HttpStatusCode]::NotFound)
            {
                # The product does not have any existing revision information, so it will be created

                [int]$newRevision = 0;
                if ($RevisionOverride -lt 0)
                {
                    $newRevision = 1;
                    Write-Host "No revision information was found for '$ProductName'. Creating a revision for '$RevisionKey' with a value of 1...";
                }
                else
                {
                    $newRevision = $RevisionOverride;
                    Write-Host "No revision information was found for '$ProductName'. Creating a revision for '$RevisionKey' with the override value of '$newRevision'...";
                }
                [string]$setRequestJson = @{ id = $urlEncodedProductName; $urlEncodedRevisionKey = $newRevision } | ConvertTo-Json;

                [System.Net.Http.StringContent]$setRequestContent = New-Object System.Net.Http.StringContent($setRequestJson);
                $setRequestContent.Headers.ContentType = "application/json";
                [string]$setUrl = "_apis/ExtensionManagement/InstalledExtensions/csdahlberg/versioning/Data/Scopes/Default/Current/Collections/Revisions/Documents";
                $setResponse = $httpClient.PostAsync($setUrl, $setRequestContent).GetAwaiter().GetResult();

                if ($setResponse.IsSuccessStatusCode)
                {
                    $newRevision;
                    return;
                }

                # If the value was created by some other process, a BadRequest status will be returned with a typeKey value of "DocumentExistsException" in the response body.
                if ($setResponse.StatusCode -eq [System.Net.HttpStatusCode]::BadRequest)
                {
                    $setResponseJson = $setResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                    $setResponseObject = $setResponseJson | ConvertFrom-Json;
                    if ($setResponseObject.typeKey -eq "DocumentExistsException")
                    {
                        Write-Host "Creating the initial revision information for '$ProductName' failed, probably because it was created by another process.";
                    }
                    else
                    {
                        Write-Host "##vso[task.logissue type=error]An error was returned attempting to create the initial revision information for '$ProductName': $setResponse";
                        Write-Host "##vso[task.complete result=Failed]DONE";
                        Exit;
                    }
                }
                else
                {
                    Write-Host "##vso[task.logissue type=error]An error was returned attempting to create the initial revision information for '$ProductName': $setResponse";
                    Write-Host "##vso[task.complete result=Failed]DONE";
                    Exit;
                }
            }
            else
            {
                Write-Host "##vso[task.logissue type=error]An unexpected response was returned attempting to get existing revision information for '$ProductName': $getResponse";
                Write-Host "##vso[task.complete result=Failed]DONE";
                Exit;
            }
        }
        catch [System.Exception]
        {
            Write-Host "##vso[task.logissue type=error]An exception was thrown attempting to get or set the revision for '$RevisionKey': $_";
            Write-Host "##vso[task.complete result=Failed]DONE";
            Exit;
        }
        finally
        {
            if ($setResponse -ne $null)
            {
                $setResponse.Dispose();
            }
            if ($getResponse -ne $null)
            {
                $getResponse.Dispose();
            }
            if ($httpClient -ne $null)
            {
                $httpClient.Dispose();
            }
        }

        $attempts += 1;
    }

    Write-Host "##vso[task.logissue type=error]ERROR: The revision for '$RevisionKey' of '$ProductName' could not be updated after 5 attempts. Giving up.";
    Write-Host "##vso[task.complete result=Failed]DONE";
    Exit;
}

Add-Type -AssemblyName "System.Net.Http, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
Add-Type -AssemblyName "System.Web, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a";
Add-Type -AssemblyName "System.Xml, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089";

# The build date number is the number of days since 2000-01-01
[System.DateTime]$dateNumberStart = (New-Object -TypeName System.DateTime -ArgumentList 2000,1,1,0,0,0).ToUniversalTime();
[System.DateTime]$dateNumberEnd = [System.DateTime]::UtcNow;

[int]$dateNumber = (New-TimeSpan -Start $dateNumberStart -End $dateNumberEnd).TotalDays;

[string]$assemblyVersion = "$MajorVersion.$MinorVersion.$PatchVersion.0";

[int]$assemblyFileVersionRevision = CreateOrIncrementRevision -ProductName $ProductName -RevisionKey "AssemblyFileVersion $MajorVersion.$MinorVersion.$dateNumber" -RevisionOverride $AssemblyFileVersionRevisionOverride;
[string]$assemblyFileVersion = "$MajorVersion.$MinorVersion.$dateNumber.$assemblyFileVersionRevision";

[string]$assemblyInformationalVersionSuffix;
[string]$assemblyInformationalVersion;
if ([string]::IsNullOrWhiteSpace($PrereleaseLabel))
{
    $assemblyInformationalVersionSuffix = $null;
    $assemblyInformationalVersion = "$MajorVersion.$MinorVersion.$PatchVersion";
}
else
{
    [int]$assemblyInformationalVersionRevision = CreateOrIncrementRevision -ProductName $ProductName -RevisionKey "AssemblyInformationalVersion $MajorVersion.$MinorVersion.$PatchVersion-$PrereleaseLabel" -RevisionOverride $PackagePrereleaseRevisionOverride;
    $assemblyInformationalVersionSuffix = $PrereleaseLabel + $assemblyInformationalVersionRevision.ToString("D2");
    $assemblyInformationalVersion = "$MajorVersion.$MinorVersion.$PatchVersion-$assemblyInformationalVersionSuffix";
}

StampVersions -Directory $SourcesDirectory -AssemblyVersion $assemblyVersion -AssemblyFileVersion $assemblyFileVersion -AssemblyInformationalVersionSuffix $assemblyInformationalVersionSuffix -AssemblyInformationalVersion $assemblyInformationalVersion;
