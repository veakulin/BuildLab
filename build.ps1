param (
    [string]$buildDir = "."
)

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

$headers    = @{'Accept'='application/vnd.github.v3+json'}
$owner      = "veakulin"
$repo       = "BuildLab"
$githubApi  = "https://api.github.com/repos/$owner/$repo"
$branch     = "main"
$commit     = "$owner-$repo-$(((Invoke-WebRequest -Headers $headers -Uri "$githubApi/branches/$branch" | ConvertFrom-Json).commit.sha).Substring(0, 7))"

$buildDir         = Resolve-Path $buildDir
$commitDir        = "$buildDir\$commit" 
$commitZipball    = "$buildDir\$commit.zip" 
$srcDir           = "$buildDir\src"
$releaseDir       = "$buildDir\release"
$binDir           = "$releaseDir\bin"
$pdbDir           = "$releaseDir\symbols"
$releaseZipball   = "$releaseDir\bin.zip"

$CPPAppSrcDir = "$srcDir\CPPApp"
$CSLibSrcDir  = "$srcDir\CSLib"
$CSAppSrcDir  = "$srcDir\CSApp"

$CPPAppBinDir = "$binDir\CPPApp"
$CSLibBinDir  = "$binDir\CSLib"
$CSAppBinDir  = "$binDir\CSApp"

# Загружаем исходники
Invoke-WebRequest -Headers $headers -Uri "$githubApi/zipball/$branch" -OutFile $commitZipball
Expand-Archive -Path $commitZipball -DestinationPath $buildDir -Force
Rename-Item -Path $commitDir -NewName $srcDir

# Настраиваем проекты с помощью файлов .targets
"<Project><PropertyGroup Condition=`"'`$(Configuration)|`$(Platform)'=='Release|Win32'`"><OutDir>$CPPAppBinDir\x86\</OutDir></PropertyGroup><PropertyGroup Condition=`"'`$(Configuration)|`$(Platform)'=='Release|x64'`"><OutDir>$CPPAppBinDir\x64\</OutDir></PropertyGroup><ItemDefinitionGroup Condition=`"'`$(Configuration)'=='Release'`"><ClCompile><DebugInformationFormat>ProgramDatabase</DebugInformationFormat></ClCompile><Link><GenerateDebugInformation>true</GenerateDebugInformation></Link></ItemDefinitionGroup></Project>" | Out-File -FilePath "$CPPAppSrcDir\Directory.Build.targets"
"<Project><PropertyGroup Condition=`" '`$(Configuration)|`$(Platform)' == 'Release|AnyCPU' `"><DebugType>pdbonly</DebugType></PropertyGroup></Project>" | Out-File -FilePath "$CSLibSrcDir\Directory.Build.targets"
"<Project><PropertyGroup Condition=`" '`$(Configuration)|`$(Platform)' == 'Release|AnyCPU' `"><DebugType>pdbonly</DebugType><OutDir>$CSAppBinDir\</OutDir></PropertyGroup></Project>" | Out-File -FilePath "$CSAppSrcDir\Directory.Build.targets"

# Собираем
msbuild $CPPAppSrcDir /p:Configuration=Release,Platform=Win32
msbuild $CPPAppSrcDir /p:Configuration=Release,Platform=x64
msbuild $CSAppSrcDir /p:Configuration=Release

# Перемещаем символы
xcopy $binDir\*.pdb $pdbDir\ /syq
Get-ChildItem -Path $binDir -Include *.pdb -Recurse | Remove-Item

# Готовим манифест
@(Get-ChildItem $binDir -Recurse -File -Include *.exe,*.dll | `
      Foreach-Object { @{ file = $_.FullName.Replace($binDir, "").TrimStart('\'); 
                          length = $_.Length;
                          hash = (Get-FileHash $_ -Algorithm SHA1).hash;
                          hashType = "sha1" } }) | ConvertTo-Json | Out-File -FilePath "$binDir\Manifest"

# Упаковываем
Compress-Archive -Path "$binDir\*" -DestinationPath $releaseZipball -CompressionLevel Optimal

# Прибираемся
Remove-Item -Path $commitZipball
Remove-Item -Path $srcDir -Recurse
Remove-Item -Path $binDir -Recurse