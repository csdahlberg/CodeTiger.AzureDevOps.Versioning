import tl = require('azure-pipelines-task-lib');
import vm = require('azure-devops-node-api');
import lim = require('azure-devops-node-api/interfaces/LocationsInterfaces');
import { promises as fs } from 'fs';
import glob = require('glob');
import xmldom = require("xmldom");
import xpath = require("xpath");


function isNullOrWhiteSpace(value : string | null | undefined)
{
    return value == null || value.trim() === '';
}

function parseNumberOrDefault(value : string | null | undefined) : number | null {
    if (!value) {
        return null;
    }

    return Number.parseInt(value);
}

function formatWithLeadingZeros(value : number, length : number) : string {
    let formattedValue = value.toString();
    while (formattedValue.length < length) {
        formattedValue = '0' + formattedValue;
    }
    return formattedValue;
}

function banner(title: string): void {
    console.log("=======================================");
    console.log(`\t${title}`);
    console.log("=======================================");
}

function logDebug(message : String)
{
    const isDebugEnabled = process.env["SYSTEM_DEBUG"];
    if (isDebugEnabled && (isDebugEnabled.toUpperCase() == 'TRUE' || isDebugEnabled == '1'))
    {
        console.log(message);
    }
}

async function getApi(serverUrl: string): Promise<vm.WebApi> {
    return new Promise<vm.WebApi>(async (resolve, reject) => {
        try {
            let token = process.env["SYSTEM_ACCESSTOKEN"];
            if (!token)
            {
                throw new Error("The SYSTEM_ACCESSTOKEN environment variable is not set. The Stamp Version"
                    + " Information build task requires access to the OAuth token to store revision numbers."
                    + " Please enable the 'Allow Scripts to access the OAuth Token' option for this build"
                    + " phase.");
            }

            let authHandler = vm.getPersonalAccessTokenHandler(token);
            let option = undefined;

            let vsts: vm.WebApi = new vm.WebApi(serverUrl, authHandler, option);
            let connData: lim.ConnectionData = await vsts.connect();
            resolve(vsts);
        }
        catch (err) {
            reject(err);
        }
    });
}

async function getWebApi(): Promise<vm.WebApi>
{
    const serverUrl = process.env["SYSTEM_TEAMFOUNDATIONCOLLECTIONURI"];

    if (!serverUrl)
    {
        throw new Error("The SYSTEM_TEAMFOUNDATIONCOLLECTIONURI environment variable is not set.");
    }

    return await getApi(serverUrl);
}

async function stampVersionsInAssemblyInfoFile(
    assemblyInfoFile : string,
    assemblyVersion : string,
    assemblyFileVersion : string,
    assemblyInformationalVersion : string) : Promise<boolean>
{
    logDebug(`Looking for version information to update in '${assemblyInfoFile}'...`);
    
    const originalContent = await fs.readFile(assemblyInfoFile, "binary");
    
    const assemblyVersionRegex = /(\[\s*assembly\s*:\s*AssemblyVersion(Attribute)?\s*\(\s*\")(.*)(\"\s*\)\s*\])/;
    const assemblyFileVersionRegex = /(\[\s*assembly\s*:\s*AssemblyFileVersion(Attribute)?\s*\(\s*\")(.*)(\"\s*\)\s*\])/;
    const assemblyInformationalVersionRegex = /(\[\s*assembly\s*:\s*AssemblyInformationalVersion(Attribute)?\s*\(\s*\")(.*)(\"\s*\)\s*\])/;

    const newContent = originalContent.replace(assemblyVersionRegex, '$1' + assemblyVersion + '$4');
    if (newContent !== originalContent)
    {
        console.log(`Set AssemblyVersion to '${assemblyVersion}' in '${assemblyInfoFile}'`);
    }

    const newContent2 = newContent.replace(assemblyFileVersionRegex, '$1' + assemblyFileVersion + '$4');
    if (newContent2 !== newContent)
    {
        console.log(`Set AssemblyFileVersion to '${assemblyFileVersion}' in '${assemblyInfoFile}'`);
    }

    const newContent3 = newContent2.replace(assemblyInformationalVersionRegex, '$1' + assemblyInformationalVersion + '$4');
    if (newContent3 !== newContent2)
    {
        console.log(`Set AssemblyInformationalVersion to '${assemblyInformationalVersion}' in '${assemblyInfoFile}'`);
    }

    if (newContent3 !== originalContent)
    {
        logDebug(`Writing new contents to '${assemblyInfoFile}'...`);
        await fs.writeFile(assemblyInfoFile, newContent3, "binary");
        logDebug(`Finished writing new contents to '${assemblyInfoFile}'.`);
        return true;
    }

    logDebug(`'${assemblyInfoFile}' was not changed.`);
    return false;
}

async function stampVersionsInNetstandardCsprojFile(
    csprojFile : string,
    assemblyVersion : string,
    assemblyFileVersion : string,
    assemblyInformationalVersion : string,
    assemblyInformationalVersionSuffix : string | null,
    shouldSetReleaseNotes : boolean,
    releaseNotes : string | null,
    sourceVersion : string | null) : Promise<boolean>
{
    logDebug(`Looking for version information to update in '${csprojFile}'...`);

    const originalContent = await fs.readFile(csprojFile, "binary");
    const doc = new xmldom.DOMParser().parseFromString(originalContent);
    
    // Set /Project/PropertyGroup/Version elements to assemblyInformationalVersion
    let versionNodes = xpath
        .select("/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'Version']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = assemblyInformationalVersion;
        console.log(`Set /Project/PropertyGroup/Version to '${assemblyInformationalVersion}' in '${csprojFile}'.`);
    }

    // Set /Project/PropertyGroup/VersionPrefix elements to assemblyVersion
    versionNodes = xpath.select(
        "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'VersionPrefix']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = assemblyVersion;
        console.log(`Set /Project/PropertyGroup/VersionPrefix to '${assemblyVersion}' in '${csprojFile}'.`);
    }

    // Set /Project/PropertyGroup/VersionSuffix elements to assemblyInformationalVersionSuffix
    versionNodes = xpath.select(
        "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'VersionSuffix']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = assemblyInformationalVersionSuffix;
        console.log(`Set /Project/PropertyGroup/VersionSuffix to '${assemblyInformationalVersionSuffix}' in '${csprojFile}'.`);
    }

    // Set /Project/PropertyGroup/FileVersion elements to assemblyFileVersion
    versionNodes = xpath.select(
        "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'FileVersion']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = assemblyFileVersion;
        console.log(`Set /Project/PropertyGroup/FileVersion to '${assemblyFileVersion}' in '${csprojFile}'.`);
    }

    // Set /Project/PropertyGroup/PackageVersion elements to assemblyInformationalVersion
    versionNodes = xpath.select(
        "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'PackageVersion']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = assemblyInformationalVersion;
        console.log(`Set /Project/PropertyGroup/PackageVersion to '${assemblyInformationalVersion}' in '${csprojFile}'.`);
    }

    if (shouldSetReleaseNotes)
    {
        // Set /Project/PropertyGroup/PackageReleaseNotes elements to releaseNotes
        versionNodes = xpath.select(
            "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'PackageReleaseNotes']", doc);
        for (let versionNode of versionNodes as Array<Node>)
        {
            versionNode.textContent = releaseNotes;
            console.log(`Set Project/PropertyGroup/PackageReleaseNotes to the specified release notes in '${csprojFile}'.`);
        }
    }

    versionNodes = xpath.select(
        "/*[local-name() = 'Project']/*[local-name() = 'PropertyGroup']/*[local-name() = 'RepositoryCommit']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = sourceVersion;
        console.log(`Set Project/PropertyGroup/RepositoryCommit to '${sourceVersion}' in '${csprojFile}'.`);
    }

    const newContent = doc.toString();

    if (newContent !== originalContent)
    {
        logDebug(`Writing new contents to '${csprojFile}'...`);
        await fs.writeFile(csprojFile, newContent, "binary");
        logDebug(`Finished writing new contents to '${csprojFile}'.`);
        return true;
    }

    logDebug(`'${csprojFile}' was not changed.`);
    return false;
}

async function stampVersionsInNuspecFile(
    nuspecFile : string,
    version : string,
    shouldSetReleaseNotes : boolean,
    releaseNotes : string | null,
    sourceVersion : string | null) : Promise<boolean>
{
    logDebug(`Looking for version information to update in '${nuspecFile}'...`);

    const originalContent = await fs.readFile(nuspecFile, "binary");
    const doc = new xmldom.DOMParser().parseFromString(originalContent);
    
    // Set /package/metadata/version elements to version
    let versionNodes = xpath
        .select("/*[local-name() = 'package']/*[local-name() = 'metadata']/*[local-name() = 'version']", doc);
    for (let versionNode of versionNodes as Array<Node>)
    {
        versionNode.textContent = version;
        console.log(`Set /package/metadata/version to '${version}' in '${nuspecFile}'.`);
    }

    if (shouldSetReleaseNotes)
    {
        // Set /package/metadata/releaseNotes elements to releaseNotes
        let versionNodes = xpath
            .select("/*[local-name() = 'package']/*[local-name() = 'metadata']/*[local-name() = 'releaseNotes']", doc);
        for (let versionNode of versionNodes as Array<Node>)
        {
            versionNode.textContent = releaseNotes;
            console.log(`Set /package/metadata/releaseNotes to '${releaseNotes}' in '${nuspecFile}'.`);
        }
    }

    // Set /package/metadata/repository/@commit attributes to sourceVersion
    let repositoryNodes = xpath
        .select("/*[local-name() = 'package']/*[local-name() = 'metadata']/*[local-name() = 'repository']", doc);
    for (const repositoryNode of repositoryNodes as Array<Node>)
    {
        const commitAttribute = xpath.select1("@commit", repositoryNode) as Attr;
        if (commitAttribute)
        {
            commitAttribute.value = sourceVersion || "";
            console.log(`Set /package/metadata/repository/@commit to '${version}' in '${nuspecFile}'.`);
        }
    }

    const newContent = doc.toString();

    if (newContent !== originalContent)
    {
        logDebug(`Writing new contents to '${nuspecFile}'...`);
        await fs.writeFile(nuspecFile, newContent, "binary");
        logDebug(`Finished writing new contents to '${nuspecFile}'.`);
        return true;
    }

    logDebug(`'${nuspecFile}' was not changed.`);
    return false;
}

async function stampVersionsInVsixmanifestFile(
    vsixmanifestFile : string,
    version : string) : Promise<boolean>
{
    logDebug(`Looking for version information to update in '${vsixmanifestFile}'...`);

    const originalContent = await fs.readFile(vsixmanifestFile, "binary");
    const doc = new xmldom.DOMParser().parseFromString(originalContent);
    
    // Set /PackageManifest/Metadata/Identity/@Version attributes to version
    const identityNodes = xpath
        .select("/*[local-name() = 'PackageManifest']/*[local-name() = 'Metadata']/*[local-name() = 'Identity']", doc);
    for (const identityNode of identityNodes as Array<Node>)
    {
        const versionAttribute = xpath.select1("@Version", identityNode) as Attr;
        if (versionAttribute)
        {
            versionAttribute.value = version;
            console.log(`Set /PackageManifest/Metadata/Identity/@Version to '${version}' in '${vsixmanifestFile}'.`);
        }
    }

    const newContent = doc.toString();

    if (newContent !== originalContent)
    {
        logDebug(`Writing new contents to '${vsixmanifestFile}'...`);
        await fs.writeFile(vsixmanifestFile, newContent, "binary");
        logDebug(`Finished writing new contents to '${vsixmanifestFile}'.`);
        return true;
    }

    logDebug(`'${vsixmanifestFile}' was not changed.`);
    return false;
}

async function createOrIncrementRevision(
    productName : string,
    revisionKey : string,
    shouldOverrideRevision : boolean,
    revisionOverride : number | null) : Promise<number>
{
    logDebug("Getting the WebApi instance...");
    const webApi = await getWebApi();
    logDebug("Getting the IExtensionManagementApi instance...");
    const extMgmtApi = await webApi.getExtensionManagementApi();

    const urlEncodedProductName = encodeURIComponent(productName).replace(/%20/g, "+");
    const urlEncodedRevisionKey = encodeURIComponent(revisionKey).replace(/%20/g, "+");

    const maxAttempts = 5;
    let attempts = 1;

    // Make up to 5 attempts to create or update the revision
    while (attempts <= maxAttempts)
    {
        try
        {
            logDebug(`Attempting to get existing revisions for '${productName}'...`);

            const doc = await extMgmtApi.getDocumentByName("csdahlberg", "versioning", "Default", "Current",
                "Revisions", urlEncodedProductName);

            if (doc)
            {
                // The product has existing revision information, so the document should be updated

                let newRevision : number;

                const currentRevisionRaw = doc[urlEncodedRevisionKey];
                const currentRevision = Number(currentRevisionRaw);

                if (currentRevisionRaw || currentRevision === 0)
                {
                    // The version has a revision set for it, so it will be updated

                    if (shouldOverrideRevision)
                    {
                        newRevision = revisionOverride || 0;
                        doc[urlEncodedRevisionKey] = newRevision;
                        logDebug(`A revision of '${currentRevision}' already exists for '${revisionKey}' of '${productName}'. Setting it to the override value of '${newRevision}'...`);
                    }
                    else
                    {
                        newRevision = currentRevision + 1;
                        doc[urlEncodedRevisionKey] = newRevision;
                        logDebug(`A revision of '${currentRevision}' already exists for '${revisionKey}' of '${productName}'. Incrementing it to '${newRevision}'...`);
                    }
                }
                else
                {
                    // The version does not have a revision set for it, so it will be created.

                    if (shouldOverrideRevision)
                    {
                        newRevision = revisionOverride || 0;
                        doc[urlEncodedRevisionKey] = newRevision;
                        logDebug(`An initial revision of the override value '${newRevision}' will be created for '${revisionKey}' of '${productName}'.`);
                    }
                    else
                    {
                        newRevision = 0;
                        doc[urlEncodedRevisionKey] = newRevision;
                        logDebug(`An initial revision of '${newRevision}' will be created for '${revisionKey}' of '${productName}'.`);
                    }
                }

                logDebug(`Updating the revisions document for '${productName}'...`);
                let updateResponse = await extMgmtApi.updateDocumentByName(doc, "csdahlberg", "versioning", "Default", "Current", "Revisions");
                logDebug(`Completed updating the revisions document for '${productName}'.`);
                
                return newRevision;
            }
            else
            {
                // The product does not have any existing revision information, so it will be created.

                const newRevision = 0;

                const doc : any = new Object();
                doc[urlEncodedRevisionKey] = newRevision;

                logDebug(`Creating the revisions document for '${productName}'...`);
                let createResponse = await extMgmtApi.createDocumentByName(doc, "csdahlberg", "versioning", "Default", "Current", "Revisions");
                logDebug(`Completed creating the revisions document for '${productName}'.`);

                return newRevision;
            }
        }
        catch (ex)
        {
            logDebug(`Exception thrown attempting to increment revision number: ${JSON.stringify(ex)}`);
        }

        attempts += 1;
    }

    throw new Error(`The revision for '${revisionKey}' of '${productName}' could not be updated after ${maxAttempts} attempts. Giving up."`);
}

async function stampVersions(
    assemblyVersion : string,
    assemblyFileVersion : string,
    assemblyInformationalVersion : string,
    assemblyInformationalVersionSuffix : string | null,
    shouldSetReleaseNotes : boolean,
    releaseNotes : string | null,
    sourceVersion : string | null) : Promise<void>
{
    const sourcesDirectory = tl.getPathInput("SourcesDirectory", true)!;

    console.log(`Searching for files in '${sourcesDirectory}' to stamp version info in...`);

    const allPaths = tl.find(sourcesDirectory);
    
    let wereAnyFilesUpdated = false;

    // Update *AssemblyInfo.cs files
    let files = tl.match(allPaths, '**/*AssemblyInfo.cs');
    for (let assemblyInfoFile of files)
    {
        const wasFileUpdated = await stampVersionsInAssemblyInfoFile(assemblyInfoFile, assemblyVersion, assemblyFileVersion, assemblyInformationalVersion);
        if (wasFileUpdated) { wereAnyFilesUpdated = true; }
    }

    // Update *.csproj files
    files = tl.match(allPaths, '**/*.csproj');
    for (let csprojFile of files)
    {
        const wasFileUpdated = await stampVersionsInNetstandardCsprojFile(csprojFile, assemblyVersion, assemblyFileVersion, assemblyInformationalVersion, assemblyInformationalVersionSuffix, shouldSetReleaseNotes, releaseNotes, sourceVersion)
        if (wasFileUpdated) { wereAnyFilesUpdated = true; }
    }

    // Update *.nuspec files
    files = tl.match(allPaths, '**/*.nuspec');
    for (let nuspecFile of files)
    {
        const wasFileUpdated = await stampVersionsInNuspecFile(nuspecFile, assemblyInformationalVersion, shouldSetReleaseNotes, releaseNotes, sourceVersion);
        if (wasFileUpdated) { wereAnyFilesUpdated = true; }
    }

    // Update *.vsixmanifest files
    files = tl.match(allPaths, '**/*.vsixmanifest');
    for (let vsixFile of files)
    {
        const wasFileUpdated = await stampVersionsInVsixmanifestFile(vsixFile, assemblyFileVersion);
        if (wasFileUpdated) { wereAnyFilesUpdated = true; }
    }

    if (!wereAnyFilesUpdated)
    {
        tl.warning("No files were updated.");
    }
}

async function run()
{
    try
    {
        banner("Stamp Version Information");

        const productName = tl.getInput("ProductName", true)!;
        const majorVersion = tl.getInput("MajorVersion");
        const minorVersion = tl.getInput("MinorVersion");
        const patchVersion = tl.getInput("PatchVersion");
        const shouldCreatePrereleaseVersion = tl.getBoolInput("ShouldCreatePrereleaseVersion") ?? true;
        const prereleaseLabel = tl.getInput("PrereleaseLabel");
        const shouldSetReleaseNotes = tl.getBoolInput("ShouldSetReleaseNotes") ?? false;
        const releaseNotes = tl.getInput("ReleaseNotes") ?? null;
        const sourceVersion = process.env["BUILD_SOURCEVERSION"] ?? null;
        const shouldOverrideAssemblyFileVersionRevision
            = tl.getBoolInput("ShouldOverrideAssemblyFileVersionRevision") ?? false;
        const assemblyFileVersionRevisionOverride = parseNumberOrDefault(tl.getInput("AssemblyFileVersionRevisionOverride"));
        const shouldOverridePackagePrereleaseVersionRevision
            = tl.getBoolInput("ShouldOverridePackagePrereleaseVersionRevision") ?? false;
        const packagePrereleaseVersionRevisionOverride = parseNumberOrDefault(tl.getInput("PackagePrereleaseVersionRevisionOverride"));

        if (shouldCreatePrereleaseVersion && isNullOrWhiteSpace(prereleaseLabel))
        {
            throw new Error("No Prerelease label was specified, but it is required because 'Create Prerelease Version?' is true.");
        }

        const now = new Date();
        const nowUtc = new Date(now.getTime() + now.getTimezoneOffset() * 60000);
        const baseTimeUtc = new Date(2000, 0, 1);
        
        const millisecondsPerDay = 24 * 60 * 60 * 1000;
        const dateNumber : number = Math.floor((nowUtc.getTime() - baseTimeUtc.getTime()) / millisecondsPerDay);

        const assemblyVersion = `${majorVersion}.${minorVersion}.${patchVersion}.0`;

        const assemblyFileVersionRevisionKey = `AssemblyFileVersion ${majorVersion}.${minorVersion}.${dateNumber}`;
        const assemblyFileVersionRevision = await createOrIncrementRevision(productName,
            assemblyFileVersionRevisionKey, shouldOverrideAssemblyFileVersionRevision,
            assemblyFileVersionRevisionOverride);

        let assemblyFileVersion = `${majorVersion}.${minorVersion}.${dateNumber}.${assemblyFileVersionRevision}`;

        var assemblyInformationalVersionSuffix : string | null;
        var assemblyInformationalVersion : string;
        if (shouldCreatePrereleaseVersion)
        {
            const assemblyInformationalVersionRevisionKey = `AssemblyInformationalVersion ${majorVersion}.${minorVersion}.${patchVersion}-${prereleaseLabel}`;
            const assemblyInformationalVersionRevision = await createOrIncrementRevision(productName,
                assemblyInformationalVersionRevisionKey, shouldOverridePackagePrereleaseVersionRevision,
                packagePrereleaseVersionRevisionOverride);
            assemblyInformationalVersionSuffix = `${prereleaseLabel}${formatWithLeadingZeros(assemblyInformationalVersionRevision, 2)}`;
            assemblyInformationalVersion = `${majorVersion}.${minorVersion}.${patchVersion}-${assemblyInformationalVersionSuffix}`;
        }
        else
        {
            assemblyInformationalVersionSuffix = null;
            assemblyInformationalVersion = `${majorVersion}.${minorVersion}.${patchVersion}`;
        }

        await stampVersions(assemblyVersion, assemblyFileVersion, assemblyInformationalVersion,
            assemblyInformationalVersionSuffix, shouldSetReleaseNotes, releaseNotes, sourceVersion);
    }
    catch (err)
    {
        tl.setResult(tl.TaskResult.Failed, err.message, true);
    }
}

run();