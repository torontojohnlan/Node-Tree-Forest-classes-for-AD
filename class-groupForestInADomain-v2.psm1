<#
    The "ForestOfGroupTrees" class is used to enumerate all groups in given domain, then construct a tree per group,
    thus form a forest of group trees. 
    This forest can be used to print group structure, to get statistics of groups, etc. as demo'ed as this script shows

    Dependency:
        class-JohnAD.ps1
        class-groupTree.ps1
        Also other files that above class*.ps1 might depend on, such as SIDTable

    Usage:
        At end of this file

    v2: 
        - adds short group name/domain info to output
        - buildig loops as special trees. It's now part of forest constructor instead of a separate call to [SCC]::getSCCs
#>
using module  ".\class-JohnAD-v2.psm1"
using module  ".\class-groupTree-v2.psm1"

#region SCC class
class SCC{ # This class is used to identify loops. Not for storing any info for later use
    <#
        # Node is represented by this.graphNodes
        # edge is represented by this.graphNodes[DN].nextNodes (which is a copy of input object $groups.members
    
    #>
        
    #region properties. SCC class does not deal with any AD-specific attributes. This should remain purely for finding SCC only
        [int32] $globalIndex
        [System.Collections.Generic.stack[string]]$stack  # store group DN in stack so we can locate actual node with DN
        [hashtable]$graphNodes # {DN,stats+members} pair
        [string[]]$keyRepository # this is need only because we can't use a hashtable itself to do foreach. So we add an extra copy of keys for where foreach against our $graphNodes is used
    
    <#	
    NOTE: Keep in mind that hashtable itself is NOT enumeratable by itself. You will have to call .getEnumerator() to get an enumeratable collection.
        Even then, you can't change the hashtable itself while foreach thru items in result of getEnumerator().
        For this reason, we create $this.keyRepository array out of $graphNodes for enumeration purpose
    #>
    #endregion properties
    
    #region constructor

    #region Constructor #1 - build SCC graph from AD group table
    SCC([hashtable]$groupTable){# $groupTable is {[DN],[string[]]DN_of_members} pair. Constructor fills in other tracking numbers that are required by SCC algo in PScustomObject
        $this.globalIndex=0
        $this.stack = [System.Collections.Generic.stack[string]]::new()
        $this.graphNodes=@{}
        $this.keyRepository = $groupTable.Keys.clone()
        foreach($key in $this.keyRepository){
            $newNode=[pscustomobject]@{
                index=[int32] -1
                lowlink=[int32] -1
                onStack=[boolean] $false
                #groupDN=$node.key
                nextNodes=[string[][]] $groupTable[$key]
            }
            $this.graphNodes[($key)]=$newNode	# add new node to nodes table
        }
    } 
    #endregion Constructor #1

    #region constructor #2
    # we could have constructor to from other type of source
    #endregion constructor #2

    #endregion constructor 

    #region methods
    [string[][]] getSCCs(){ # returns [DN[][]] only. No AD hierarchy info as SCC deals with only finding loops
        # using Tarjan's SCC algo to find circular nesting
        # (https://www.thealgorists.com/Algo/GraphTheory/Tarjan/SCC)
        
        [string[][]] $SCCsFoundInGraph=@() 
        foreach( $key in $this.keyRepository){
            if ($this.graphNodes[$key].index -eq -1){ # unvisited
                [string[][]] $nodeResult=$this.findStrongconnect($key)
                $SCCsFoundInGraph += $nodeResult
            }
        }
        return $SCCsFoundInGraph
    }

    hidden [string[][]] findStrongconnect([string]$currentNode){ # returns [DN[][]] only. No hierarchy info as SCC deals with only finding loops
        # parameter $currentNode is DN string. we use this DN as pointer to find the actual node and do stats update

        # Set the depth $index for $node to the smallest unused $index
        # in this function: currentNode --> $this.graphNodes[$currentNode]
        
        $this.graphNodes[$currentNode].index = $this.globalIndex
        $this.graphNodes[$currentNode].lowlink = $this.globalIndex
        $this.globalIndex = $this.globalIndex + 1
        $this.stack.push($currentNode)
        $this.graphNodes[$currentNode].onStack = $true
         
        [string[][]]$SCCsFoundInNode = @()
        # Consider successors of $node
        $nextNodes=$this.graphNodes[$currentNode].nextNodes.clone()
        foreach ($nextNode in $nextNodes){  #DFS next tier of nodes
            if ($this.graphNodes[$nextNode].index -eq -1) {       # Successor $nextNode has not yet been visited; recurse on it
                $SCCsFoundInNode = $this.findStrongconnect($nextNode)
                if ($this.graphNodes[$currentNode].lowlink -gt $this.graphNodes[$nextNode].lowlink){
                    $this.graphNodes[$currentNode].lowlink =($this.graphNodes[$nextNode].lowlink)
                }
            }
            else {if ($this.graphNodes[$nextNode].onStack -eq $true) {
                # Successor $nextNode is in stack $this.stack and hence in the current SCC
                # If $nextNode is not on stack, { ($node, $nextNode) is an edge pointing to an SCC already found and must be ignored
                # Note: The next line may look odd - but is correct.
                # It says $nextNode.index not $nextNode.lowlink; that is deliberate and from the original paper
                if ($this.graphNodes[$currentNode].lowlink -gt $this.graphNodes[$nextNode].index){
                    $this.graphNodes[$currentNode].lowlink = ($this.graphNodes[$nextNode].index)
                }
            }}
        }
        
        # If $node is a root node, pop the stack and generate an SCC
        if (($this.graphNodes[$currentNode].lowlink) -eq ($this.graphNodes[$currentNode].index)) {
            #start a new strongly connected component
            $currentResult=@()  # one SCC is an string array
            do {
                $stackTop = $this.stack.pop()
                $this.graphNodes[$stackTop].onStack = $false
                $currentResult +=,$stackTop        #[add $stackTop to current strongly connected component
            }until ( $stackTop -eq $currentNode)
            $SCCsFoundInNode +=,$currentResult 
        }
        return $SCCsFoundInNode
    }
    #endregion methods
}
    
#region SCC demo
<#
$scc=[SCC]::new($groups) 	# $groups is hashtable of @{groupDN,memberDN[]}
$result=$scc.getSCCs()
#>
#endregion SCC demo
#endregion SCC class

class ForestOfGroupTrees{ # "forest in a computer graph sense. Collection of trees. Not to be confused with AD forest
    #region properties
    # static [string] $logFileBasePath = "C:\temp\"
    # static [string[]] $DomainList=[ADext]::DCTable.GetEnumerator().name
    #static [string[]] $excludedGroups=@("Domain Users",    "Domain Computers")
    [string[]] $groupObjCategoryString # this is added as a property only for convenience purpose. This is a domain specific string for objectCategory filter
    #[hashtable] $forestInventory = @{} # for later consideration. It's too costly to maintain a forest wide inventory 
    [Tree[]]$trees=@()

    [loop[]]$loops # used to store circular nesting results. Data type TBD. Speciall trees will be created for each loop, and stored in this.trees
    <# 
        Normally whether to create a tree (i.e. determine if a group can be treeTop) depends on its "memberof" attribute. 
        A group can be treeTop only when its "memberOf" is empty (no parent). However this method won't work for
        circular nesting because all groups in a loop will have at least one parent

        All groups in a circular chain have same nesting level, which is the total number of groups in such loop
    #>
    #endregion properties
    
    ForestOfGroupTrees([string]$domainFQDN) { # construct group forest-graph for a domain, begins
        [hashtable] $loopCandidates=@{} 
        <# $leftoverGroup will be identical to $groups. Then elments that are valid for tree will be removed. What's left are only member of a loop
        $loopCandidates will be a clone of $allGroups.DN at first, then whenever a group is being inventoried into trees, this group
        will be removed from $loopCandidates. When all trees are surveyed, what are left in $cicrcularCache can only be part of a 
        circular chain (not part of a tree but yet having parent). We will then still create a "tree" using any group in loop as treeTop
         #>
        #region read AD
        $domainObj=get-addomain $domainFQDN -server ([ADext]::dctable[$domainFQDN])
        $this.groupObjCategoryString="CN=Group,CN=Schema,CN=Configuration,"+[ADext]::fqdn2dn($domainObj.forest)
        $filter="(&(!(name=Domain Users))(!(name=domain computers))(!(name=Users))(objectCategory="+ ($this.groupObjCategoryString) + "))"
        write-host "[Info] Retrieving all groups from $domainFQDN" -ForegroundColor DarkGreen
        $groups= get-adobject -ldapfilter $filter -properties samAccountName,enabled,member,memberof -server ([ADext]::dctable[$domainFQDN])
        #endregion read AD
        foreach($group in $groups){  #build priliminary $loopCandidates
            $groupInfo=[PSCustomObject]@{
                domain = $domainObj.NetBIOSName
                ID = $group.samAccountName
                members = @()
            }
            foreach($memberDN in $group.member){
                $memberNode=[PSCustomObject]@{
                    DN=$memberDN
                    domain=""  # will be populated later after candidate list is truly trimmed to have circular nesting only
                    ID=""
                    Enabled = $true
                }
                $groupInfo.members += $memberNode
            }
            $loopCandidates[$group.distinguishedName]=$groupInfo
        }

        #region build none-loop trees AND finalize $loopCandidates  
        #$newLineFlag=0
        foreach ($group in $groups){ # enumerate thru groups to build non-loop trees
            #$newLineFlag +=1
            <#if ($newLineFlag -ge 50){
                $newLineFlag =0
                write-host "." -ForegroundColor Green
            }
            else {write-host "." -NoNewline -ForegroundColor Green}
            #>
            if (($group.memberof).count -eq 0){ # create a tree only if the group is not child of any other
                $tree = [Tree]::new($group.distinguishedName)

                $tree.inventory.getEnumerator().name | foreach {$loopCandidates.Remove($_)} # can't be part of a loop, remove it from candidate list
                # later consideration: add code here to merge new Tree.inventory into forest.inventory
                # forest.count is not a simple sum of tree.count because same group can exist in different trees therefore be counted more than once
                $this.trees += $tree
            } #creat tree ends
        } # enumerate groups ends
        #endregion build non-loop trees

        #region build loops
        
        # after all non-loop trees are constructed, there will be some groups left. These are the ones that in a loop nesting AND not
        # in any trees that already constructed. Leftover groups are stored in $loopCandidates
        # We are going to process these group with Tarjan's SCC algo to find loops
        #
        
        # ------------------------------------
        # Data structure for $loopCandidates
        # ------------------------------------
        # [hashtable] $loopCandidates       = {key=DN, {$groupInfo}}
        # [psObject] $groupInfo             = {domain=domainName,ID=samAccountName,enabled,members=memberNode[]}
        # [psObject] $memberNode            = {DN,domain,ID,enabled}
        # ---------------------------------------------
        
        #region At this point, $loopCandiates truly contains only loop nodes.
        #fill in more info into $loopCandidates, weed out non-group members[]
        $keys=$loopCandidates.Keys.clone()
        foreach($key in $keys){
            #$members=$loopCandidates[$key].members
            $trimmedMembers=@()
            foreach($member in $loopCandidates[$key].members){
                $memberDN = $member.DN
                $DC = [adext]::dn2dc($memberDN)
                $domainName=[adext]::DN2DomainNETBiosName($memberDN)
                $mObj=get-adobject $memberDN -server $DC -Properties objectClass,samAccountName,enabled
                if($mObj.objectClass -eq "group"){
                    $member.ID = $mObj.samAccountName
                    $member.domain = $domainName
                    $trimmedMembers+=$member
                }
            }
            $loopCandidates[$key].members=$trimmedMembers
        }
        #endregion fill in more AD info into $loopCandidates

        #region convert $loopCandidates to a hashtable that SCC can use
        $sccInput=@{}
        foreach($candidate in $loopCandidates.keys){
            $sccInput[$candidate] = [string[]]$loopCandidates[$candidate].members.DN  
        }
        #endregion convert $loopCandidates to a hashtable that SCC can use

        #region build loop node from SCC results and add it to $this.loops
        $scc=[SCC]::new($sccInput) 	# SCC constructor expects input as {[DN],[string[]]DN_of_members} hashtable
        $results=$scc.getSCCs() #results is string[loops][loop member DNs], all loops
        foreach($result in $results){ #  $result is  string array of [loop member DNs]
            $loopInventory=@{}
            foreach ($loopMember in $result){
                $loopInventory[$loopMember]=$loopCandidates[$loopMember]
            }
            $loop=[loop]::new($result,$loopInventory)
            $this.loops += $loop
        }
        #endregion build loop node and add it to $this.loops
        #endregion build loops

        #region create special trees for loops and add them into this.trees[] 
        #todo: decide not to do this for now. Any use of this class should print both trees and loops
        # foreach($loop in $loops){
        #     $tree=[tree]::new($true,$loop)
        #     $this.trees += $tree
        # }
        #endregion create special trees for loops and add them into this.trees[]

    } # Forest constructore ends
} # end class ForestOfGroupTrees

#region demo section #1 - How to use forest.loops
#region misc. preparation jobs before constructing a forest
# write-host "Please type in domain name" -ForegroundColor Yellow
# write-host " Note that there is not validation aganist what you type, please ensure type correctly" -ForegroundColor Yellow
# $domainName = "johnfoo.tk" #read-host 

# $level=[Int32] (Read-Host "please specify min level from which you want to count stats")
#$tree1 = $micorpForestGraph.trees[0]
#$treeName = $tree1.treetop.toShortForm() -replace '\\','_'
#$tree1.printTree(("{0}{1}_treeView.txt" -f $logBasePath,$treeName))

# $logBasePath = "c:/temp/pstest" #read-host "type in log path, excluding ending /"
# try{$pathValid = test-path $logBasePath -ea SilentlyContinue}catch{}
# if (-not $pathValid){
#     Write-Error "File path given invalid"
#     Exit
# }
# $treeFile = "{0}\{1}_nestedGroups.csv" -f $logBasePath,$domainName
# $loopFile = "{0}\{1}_circularGroups.csv" -f $logBasePath,$domainName
# try {new-item  -itemType file $logFile -force -confirm:$false}
# catch{}
# $inventoryItem=[inventoryNode]::new() #create a tmp object just for getting its header
# $header=""
# $inventoryItem.psobject.properties.name | foreach{$header+='"'+$_+'",'}
# $header -replace ",$","" | Set-Content $treeFile
# $header -replace ",$","" | Set-Content $loopFile
# write-host "-------------- Process Begins ----------------"
#endregion misc. preparation jobs before constructing a forest

# $totalGroupCount = 0
# $totalNestingCount = 0

# $ForestOfGroupTrees = [ForestOfGroupTrees]::new($domainName)
# #$ForestOfGroupTrees.loops|foreach {write-host $_.chainString}
# $ForestOfGroupTrees.loops|foreach{$_.inventory.Values|Export-Csv $loopFile -NoTypeInformation -Append}
# ($ForestOfGroupTrees.loops[0].inventory[@(($ForestOfGroupTrees.loops[0].inventory.keys))[0]]).toCSVString()

#endregion - How to use forest.loops

#region - how to use forest.trees
# getting stats for groups that are certain level deep
# foreach ($tree in $ForestOfGroupTrees.trees){
#     $totalGroupCount += $tree.inventory.count
#     $nestedGroup=$tree.inventory.getEnumerator()|where {$_.Value.nestingLevel -ge $level}
#     $totalNestingCount += $nestedGroup.count
#     if($null -ne $nestedGroup){$nestedGroup.value | export-csv -Path $treeFile -Append}
# }  
#"`r`ntotalGroupCount:{0},totalNested:{1},percentage:{2}" -f $totalGroupCount,$totalNestingCount,($totalNestingCount/$totalGroupCount).toString("P") | Add-Content $logFile
#endregion - How to use forest.trees

#endregion demo section #1