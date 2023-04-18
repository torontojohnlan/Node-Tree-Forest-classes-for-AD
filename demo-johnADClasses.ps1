using module "./class-johnAD.psm1"
using module  ".\class-groupTree.psm1"
using module "./class-groupForestInADomain.psm1"

#region demo section #1 - How to use forest.loops
#region misc. preparation jobs before constructing a forest
write-host "Please type in domain name" -ForegroundColor Yellow
write-host " Note that there is not validation aganist what you type, please ensure type correctly" -ForegroundColor Yellow
$domainName = "johnfoo.tk" #read-host 

$level=[Int32] (Read-Host "please specify min level from which you want to count stats")
#$tree1 = $micorpForestGraph.trees[0]
#$treeName = $tree1.treetop.toShortForm() -replace '\\','_'
#$tree1.printTree(("{0}{1}_treeView.txt" -f $logBasePath,$treeName))

$logBasePath = "c:/temp/pstest" #read-host "type in log path, excluding ending /"
try{$pathValid = test-path $logBasePath -ea SilentlyContinue}catch{}
if (-not $pathValid){
    Write-Error "File path given invalid"
    Exit
}
$treeFile = "{0}\{1}_nestedGroups.csv" -f $logBasePath,$domainName
$loopFile = "{0}\{1}_circularGroups.csv" -f $logBasePath,$domainName
try {new-item  -itemType file $logFile -force -confirm:$false}
catch{}
$inventoryItem=[inventoryNode]::new() #create a tmp object just for getting its header
$header=""
$inventoryItem.psobject.properties.name | foreach{$header+='"'+$_+'",'}
$header -replace ",$","" | Set-Content $treeFile
$header -replace ",$","" | Set-Content $loopFile
write-host "-------------- Process Begins ----------------"
#endregion misc. preparation jobs before constructing a forest

$totalGroupCount = 0
$totalNestingCount = 0

$ForestOfGroupTrees = [ForestOfGroupTrees]::new($domainName)
#$ForestOfGroupTrees.loops|foreach {write-host $_.chainString}
$ForestOfGroupTrees.loops|foreach{$_.inventory.Values|Export-Csv $loopFile -NoTypeInformation -Append}
($ForestOfGroupTrees.loops[0].inventory[@(($ForestOfGroupTrees.loops[0].inventory.keys))[0]]).toCSVString()

#endregion - How to use forest.loops

#region - how to use forest.trees
# getting stats for groups that are certain level deep
foreach ($tree in $ForestOfGroupTrees.trees){
    $totalGroupCount += $tree.inventory.count
    $nestedGroup=$tree.inventory.getEnumerator()|where {$_.Value.nestingLevel -ge $level}
    $totalNestingCount += $nestedGroup.count
    if($null -ne $nestedGroup){$nestedGroup.value | export-csv -Path $treeFile -Append}
}  
#"`r`ntotalGroupCount:{0},totalNested:{1},percentage:{2}" -f $totalGroupCount,$totalNestingCount,($totalNestingCount/$totalGroupCount).toString("P") | Add-Content $logFile
#endregion - How to use forest.trees

#endregion demo section #1
